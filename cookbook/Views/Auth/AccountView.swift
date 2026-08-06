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
    @State private var isPresentingMembership = false
    @State private var signOutErrorMessage: String?

    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()

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

                    Section("Membership") {
                        Button("View Membership & Credits") {
                            isPresentingMembership = true
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
            .sheet(isPresented: $isPresentingMembership) {
                if let userID = accountState.currentUserID {
                    MembershipPaywallView(
                        userID: userID,
                        purchaseService: purchaseService,
                        claimWriter: claimWriter,
                        entitlementService: entitlementService
                    )
                }
            }
            .onChange(of: accountState.pendingFamilyUserPromoOffer) { _, isPending in
                guard isPending else { return }
                isPresentingMembership = true
                accountState.pendingFamilyUserPromoOffer = false
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
