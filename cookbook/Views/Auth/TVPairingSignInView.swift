//
//  TVPairingSignInView.swift
//  cookbook
//
//  Reached from SignInView's "Sign In from Your Phone" link on tvOS — the
//  Netflix/YouTube-TV device-code pattern: show a short code, wait for an
//  already-signed-in phone to confirm it, sign in with the resulting
//  custom token. No credentials are ever typed via the remote.
//

import SwiftUI
import SwiftData

private enum PairingScreenState: Equatable {
    case requestingCode
    case waiting(code: String)
    case expired
    case signingIn
    case error(String)
}

struct TVPairingSignInView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(\.modelContext) private var modelContext

    let pairingService: TVPairingServicing

    init(pairingService: TVPairingServicing = FirebaseTVPairingService()) {
        self.pairingService = pairingService
    }

    @State private var state: PairingScreenState = .requestingCode
    /// Regenerated every time a new code is requested — a fresh polling
    /// attempt (e.g. after "Get New Code") shouldn't have its rate-limit
    /// budget tied to a code the person gave up on.
    @State private var deviceSessionID = UUID().uuidString
    @State private var pollTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            Text("Sign In")
                .font(.potluckHeadline(40))

            switch state {
            case .requestingCode:
                ProgressView()

            case .waiting(let code):
                VStack(spacing: 32) {
                    if let qrImage = QRCodeImageGenerator.image(for: "cookbook:tvpair:\(code)") {
                        qrImage
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding()
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                    }

                    VStack(spacing: 8) {
                        Text("Go to Account → Sign In a TV on your phone")
                            .font(.potluckBody(24))
                            .multilineTextAlignment(.center)
                        Text("and enter this code, or scan the QR above:")
                            .font(.potluckBody(24))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text(code)
                            .font(.system(size: 56, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .padding(.top, 8)
                    }
                }

            case .expired:
                VStack(spacing: 16) {
                    Text("This code has expired.")
                        .font(.potluckBody(24))
                    Button("Get New Code") {
                        Task { await requestCode() }
                    }
                }

            case .signingIn:
                ProgressView("Signing in…")

            case .error(let message):
                VStack(spacing: 16) {
                    Text(message)
                        .font(.potluckBody(20))
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        Task { await requestCode() }
                    }
                }
            }
        }
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.potluckCream)
        .task {
            await requestCode()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    private func requestCode() async {
        pollTask?.cancel()
        state = .requestingCode
        deviceSessionID = UUID().uuidString
        do {
            let request = try await pairingService.requestPairingCode(deviceSessionID: deviceSessionID)
            state = .waiting(code: request.code)
            startPolling(code: request.code)
        } catch {
            state = .error("Couldn't start sign-in. Check your connection and try again.")
        }
    }

    private func startPolling(code: String) {
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                do {
                    let status = try await pairingService.checkPairingStatus(code: code, deviceSessionID: deviceSessionID)
                    switch status {
                    case .pending:
                        continue
                    case .expired:
                        state = .expired
                        return
                    case .confirmed(let token):
                        guard let token else { continue } // Already delivered to an earlier poll; nothing more to do here.
                        await signIn(withToken: token)
                        return
                    }
                } catch {
                    // A transient network hiccup shouldn't drop the person
                    // back to square one — keep polling until the code
                    // itself actually expires.
                    continue
                }
            }
        }
    }

    private func signIn(withToken token: String) async {
        state = .signingIn
        do {
            let result = try await accountState.signInWithCustomToken(token)
            try await PostSignInCoordinator.handle(result, email: nil, displayName: accountState.currentUserDisplayName, modelContext: modelContext)
        } catch {
            // If signInWithCustomToken itself already succeeded before
            // PostSignInCoordinator.handle threw, isSignedIn flips true and
            // AuthGatedRootView swaps this whole view out for RootTabView()
            // immediately — this screen's own .error state would never be
            // seen. Route that case to accountState.postSignInError instead,
            // which RootTabView checks regardless of which screen is
            // mounted; only show the local error state for a genuine
            // sign-in failure (this screen stays mounted for that case).
            if accountState.isSignedIn {
                accountState.postSignInError = "Signed in, but some of your local data may not have synced. Try relaunching."
            } else {
                state = .error("Couldn't complete sign-in. Try again.")
            }
        }
    }
}

#Preview {
    TVPairingSignInView(pairingService: FakeTVPairingService())
        .environment(AccountState(authService: FakeAuthService()))
}
