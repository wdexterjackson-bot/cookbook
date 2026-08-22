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
    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    private let publicProfileService: PublicProfileServicing = FirestorePublicProfileService()

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
                    // Deliberately not `try?` — a real failure here (e.g. a
                    // rules regression) should be visible somewhere rather
                    // than silently indistinguishable from "nothing to
                    // grant," which is exactly what made a 2026-08-09
                    // production bug (undeployed Firestore rules blocking
                    // every grant) take this long to diagnose.
                    do {
                        try await entitlementGranter.grantMissingLaunchCreditsIfEligible(userID: userID)
                    } catch {
                        print("grantMissingLaunchCreditsIfEligible failed for userID=\(userID): \(error)")
                    }
                    // Catches up on a purchase StoreKit confirmed but this
                    // device never finished submitting a claim for (offline
                    // right after paying, app killed mid-flow) — see
                    // PurchaseCoordinator.reconcileUnfinishedTransactions.
                    // Already best-effort internally, nothing to catch here.
                    await PurchaseCoordinator.reconcileUnfinishedTransactions(
                        userID: userID, purchaseService: purchaseService, claimWriter: claimWriter
                    )
                    // Same "backfill on every relaunch" reasoning as the
                    // credit grant above — an account created before
                    // publicProfiles existed (or that changed its name
                    // since) self-heals here rather than needing a fresh
                    // sign-in for friends to see its real name.
                    if let name = accountState.currentUserDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                        try? await publicProfileService.setDisplayName(name, userID: userID)
                    }
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
