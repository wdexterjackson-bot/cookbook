//
//  SignInView.swift
//  cookbook
//
//  Additive to Phase 1's local-only path (ACC-001) — reachable from
//  AccountView, never forced. Apple/Google buttons are iOS-only for now.
//

import SwiftUI
import SwiftData
#if os(iOS)
import AuthenticationServices
import GoogleSignIn
#endif

enum AuthIntent: String, CaseIterable, Identifiable {
    case signIn = "Sign In"
    case signUp = "Sign Up"
    var id: String { rawValue }
}

struct SignInView: View {
    /// False for the mandatory launch gate (AuthGatedRootView) — no Cancel
    /// button, and a successful sign-in doesn't call dismiss() since the
    /// gate swaps itself out automatically once accountState.isSignedIn
    /// flips. True (default) preserves the existing AccountView sheet use.
    var isDismissable: Bool = true

    @Environment(AccountState.self) private var accountState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Chosen before the user ever types an email — so the email/password
    /// fields below always know which action they're feeding.
    @State private var authIntent: AuthIntent = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var currentAppleNonce: String?

    private let entitlementGranter: EntitlementGranting = FirestoreEntitlementGranter()
    private let lookupService: EmailProviderLookupServicing = FirebaseEmailProviderLookupService()

    /// Google's brand wordmark colors, per letter — "Sign in with Google"
    /// with "Google" rendered the way Google's own logo colors it, rather
    /// than a plain single-color label.
    private static var googleSignInLabel: Text {
        let letters: [(Character, Color)] = [
            ("G", Color(red: 0.259, green: 0.522, blue: 0.957)),
            ("o", Color(red: 0.918, green: 0.263, blue: 0.208)),
            ("o", Color(red: 0.984, green: 0.737, blue: 0.020)),
            ("g", Color(red: 0.259, green: 0.522, blue: 0.957)),
            ("l", Color(red: 0.204, green: 0.659, blue: 0.325)),
            ("e", Color(red: 0.918, green: 0.263, blue: 0.208)),
        ]
        let wordmark = letters.reduce(Text("")) { partial, letter in
            partial + Text(String(letter.0)).foregroundColor(letter.1)
        }
        return Text("Sign in with ").foregroundColor(.primary) + wordmark
    }

    var body: some View {
        NavigationStack {
            Form {
                if !isDismissable {
                    Section {
                        Text("Sign in or create an account to use The Official Family & Friends Cookbook.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Picker("Sign In or Sign Up", selection: $authIntent) {
                        ForEach(AuthIntent.allCases) { intent in
                            Text(intent.rawValue).tag(intent)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Email") {
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("emailField")
                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("passwordField")

                    Button(authIntent.rawValue) {
                        Task { await performEmailAuth(isSignUp: authIntent == .signUp) }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isBusy)
                    .accessibilityIdentifier("signInSubmitButton")
                }

                #if os(iOS)
                Section("Or continue with") {
                    SignInWithAppleButton(.signIn) { request in
                        let nonce = NonceGenerator.randomNonce()
                        currentAppleNonce = nonce
                        request.requestedScopes = [.email, .fullName]
                        request.nonce = NonceGenerator.sha256(nonce)
                    } onCompletion: { result in
                        Task { await handleAppleCompletion(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)

                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        Self.googleSignInLabel
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                #endif

                if isBusy {
                    ProgressView()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isDismissable ? "Sign In" : "Welcome")
            .toolbar {
                if isDismissable {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private func performEmailAuth(isSignUp: Bool) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let result = isSignUp
                ? try await accountState.signUp(email: email, password: password)
                : try await accountState.signIn(email: email, password: password)
            accountState.pendingFamilyUserPromoOffer = await PostSignInCoordinator.handle(result, modelContext: modelContext, entitlementGranter: entitlementGranter)
            if isDismissable { dismiss() }
        } catch {
            errorMessage = await resolveErrorMessage(error, attemptedEmail: email, context: isSignUp ? .signUp : .signIn)
        }
    }

    /// Turns a raw auth error into a user-facing message, running a
    /// server-side EmailProviderLookupServicing lookup when the error is
    /// ambiguous (see SignInErrorMessaging) rather than showing Firebase's
    /// generic wording.
    private func resolveErrorMessage(_ error: Error, attemptedEmail: String, context: SignInAttemptContext) async -> String {
        switch SignInErrorMessaging.classify(error, attemptedEmail: attemptedEmail, context: context) {
        case .immediateMessage(let message):
            return message
        case .needsProviderLookup(let email, let lookupContext):
            let status = (try? await lookupService.resolveProviders(email: email)) ?? .notFound
            return SignInErrorMessaging.message(for: status, context: lookupContext)
        }
    }

    #if os(iOS)
    private func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            guard case .success(let authorization) = result,
                  let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let rawNonce = currentAppleNonce
            else {
                errorMessage = "Sign in with Apple failed."
                return
            }
            let authResult = try await accountState.signInWithApple(idToken: idToken, rawNonce: rawNonce)
            accountState.pendingFamilyUserPromoOffer = await PostSignInCoordinator.handle(authResult, modelContext: modelContext, entitlementGranter: entitlementGranter)
            if isDismissable { dismiss() }
        } catch {
            errorMessage = await resolveErrorMessage(error, attemptedEmail: "", context: .signUp)
        }
    }

    private func signInWithGoogle() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        guard let presenting = PresentationAnchor.topViewController() else {
            errorMessage = "Unable to present Google Sign-In."
            return
        }
        do {
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenting)
            guard let idToken = signInResult.user.idToken?.tokenString else {
                errorMessage = "Google Sign-In did not return a token."
                return
            }
            let accessToken = signInResult.user.accessToken.tokenString
            let authResult = try await accountState.signInWithGoogle(idToken: idToken, accessToken: accessToken)
            accountState.pendingFamilyUserPromoOffer = await PostSignInCoordinator.handle(authResult, modelContext: modelContext, entitlementGranter: entitlementGranter)
            if isDismissable { dismiss() }
        } catch {
            errorMessage = await resolveErrorMessage(error, attemptedEmail: "", context: .signUp)
        }
    }
    #endif
}

#Preview {
    SignInView()
        .environment(AccountState(authService: FakeAuthService()))
        .modelContainer(for: Recipe.self, inMemory: true)
}
