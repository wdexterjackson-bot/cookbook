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

struct SignInView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var currentAppleNonce: String?

    private let entitlementGranter: EntitlementGranting = FirestoreEntitlementGranter()

    var body: some View {
        NavigationStack {
            Form {
                Section("Email") {
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)

                    Button("Sign In") {
                        Task { await performEmailAuth(isSignUp: false) }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isBusy)

                    Button("Create Account") {
                        Task { await performEmailAuth(isSignUp: true) }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isBusy)
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
                        Label("Sign in with Google", systemImage: "globe")
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
            .navigationTitle("Sign In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
            await PostSignInCoordinator.handle(authResult, modelContext: modelContext, entitlementGranter: entitlementGranter)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
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
            await PostSignInCoordinator.handle(authResult, modelContext: modelContext, entitlementGranter: entitlementGranter)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif
}

#Preview {
    SignInView()
        .environment(AccountState(authService: FakeAuthService()))
        .modelContainer(for: Recipe.self, inMemory: true)
}
