//
//  AuthGatedRootView.swift
//  cookbook
//
//  Replaces the old guest-first entry point: the app now requires signing
//  in or creating an account before any use. If Firebase Auth already has
//  a persisted session (its SDK keeps this in the Keychain across
//  launches automatically — accountState.isSignedIn reflects it with zero
//  extra code here), the user skips straight through to RootTabView.
//  Otherwise they see a non-dismissible SignInView until they do.
//

import SwiftUI
import SwiftData

struct AuthGatedRootView: View {
    @Environment(AccountState.self) private var accountState

    private let entitlementGranter: EntitlementGranting = FirestoreEntitlementGranter()

    var body: some View {
        if accountState.isSignedIn {
            RootTabView()
                // "Upon launch of the application" (and every relaunch of
                // an already-signed-in session, not just fresh sign-ins) —
                // backfills whichever free launch credit(s) this account
                // hasn't received yet. A no-op once both have been granted
                // once, so safe to run unconditionally here.
                .task(id: accountState.currentUserID) {
                    guard let userID = accountState.currentUserID else { return }
                    try? await entitlementGranter.grantMissingLaunchCreditsIfEligible(userID: userID)
                }
        } else {
            SignInView(isDismissable: false)
        }
    }
}

#Preview {
    AuthGatedRootView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
