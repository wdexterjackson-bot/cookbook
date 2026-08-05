//
//  AccountView.swift
//  cookbook
//
//  Minimal account entry point for Milestone 2A — a full Profile tab
//  (purchases, memberships, data export) is later, group-lifecycle-adjacent
//  scope. This just surfaces sign-in state and a way in/out of it.
//

import SwiftUI

struct AccountView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingSignIn = false
    @State private var signOutErrorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                if accountState.isSignedIn {
                    Section("Account") {
                        LabeledContent("Signed in", value: accountState.currentUserID ?? "")
                        Button("Sign Out", role: .destructive) {
                            signOut()
                        }
                    }
                } else {
                    Section {
                        Text("Your Personal Cookbook works fully offline without an account. Sign in only when you're ready to join or create a family cookbook.")
                            .foregroundStyle(.secondary)
                        Button("Sign In / Create Account") {
                            isPresentingSignIn = true
                        }
                    }
                }

                if let signOutErrorMessage {
                    Section {
                        Text(signOutErrorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingSignIn) {
                SignInView()
            }
        }
    }

    private func signOut() {
        do {
            try accountState.signOut()
            signOutErrorMessage = nil
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AccountView()
        .environment(AccountState(authService: FakeAuthService()))
}
