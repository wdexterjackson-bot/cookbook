//
//  EntitlementGate.swift
//  cookbook
//
//  Shared paywall gate for the two actions that cost a credit: creating a
//  group/Community Cookbook (tier 2) and joining/connecting to one as a
//  non-MFB cookbook (tier 1, i.e. becoming a Pro User). Every call site
//  follows the same flow: already covered (MFB group, or already Pro) runs
//  the action immediately; a spendable credit shows a yes/no confirm before
//  spending it; no credit presents the purchase sheet instead. A successful
//  purchase auto-resumes the original action (see handlePurchaseSucceeded)
//  rather than leaving the user to retry manually — polling briefly for the
//  server-side purchase claim to land, since PurchaseCoordinator.purchase
//  returns as soon as the claim doc is written, not once a Cloud Function
//  has actually granted the credit. The purchased credit itself never
//  expires, so a poll timeout just leaves the action pending for the next
//  manual attempt rather than erroring — nothing is lost.
//

import SwiftUI

enum EntitlementGateOutcome: Equatable {
    case exempt
    case needsConfirmation(creditsAvailable: Int)
    case needsPurchase
}

enum EntitlementGate {
    static func forGroupCreation(_ entitlement: Entitlement?) -> EntitlementGateOutcome {
        let credits = entitlement?.tier2Credits ?? 0
        return credits > 0 ? .needsConfirmation(creditsAvailable: credits) : .needsPurchase
    }

    /// MFB is the one cookbook that never requires Pro User status to join.
    static func forGroupJoin(_ entitlement: Entitlement?, group: FamilyGroup) -> EntitlementGateOutcome {
        if group.isMFB == true { return .exempt }
        if entitlement?.isEffectivelyProUser == true { return .exempt }
        let credits = entitlement?.tier1Credits ?? 0
        return credits > 0 ? .needsConfirmation(creditsAvailable: credits) : .needsPurchase
    }
}

@MainActor
@Observable
final class EntitlementGateCoordinator {
    enum Kind {
        case groupCreation
        case groupJoin
    }

    var isPresentingConfirm = false
    var isPresentingPaywall = false
    var isBusy = false
    var errorMessage: String?

    private(set) var pendingKind: Kind?
    private var confirmCreditsAvailable = 0
    private var pendingAction: (() async -> Void)?
    private var pendingRecheck: ((Entitlement?) -> EntitlementGateOutcome)?

    var confirmMessage: String {
        switch pendingKind {
        case .groupCreation:
            let n = confirmCreditsAvailable
            return "Use one of your \(n) Community Cookbook creation credit\(n == 1 ? "" : "s") to create this cookbook?"
        case .groupJoin:
            return "Use your free Pro User credit to connect with this family/friends' cookbook?"
        case nil:
            return ""
        }
    }

    /// Runs `action` directly if this action is exempt from the gate;
    /// otherwise shows the confirm-or-purchase UI and `action` only runs
    /// once the user confirms spending a credit. `recheck` re-derives the
    /// same `EntitlementGateOutcome` from a fresh entitlement snapshot —
    /// needed by `handlePurchaseSucceeded` to know, after a purchase, what
    /// to do next without the caller having to thread that logic through
    /// again itself.
    func attempt(
        _ kind: Kind,
        outcome: EntitlementGateOutcome,
        recheck: @escaping (Entitlement?) -> EntitlementGateOutcome,
        action: @escaping () async -> Void
    ) async {
        errorMessage = nil
        switch outcome {
        case .exempt:
            await action()
        case .needsConfirmation(let credits):
            pendingKind = kind
            pendingAction = action
            pendingRecheck = recheck
            confirmCreditsAvailable = credits
            isPresentingConfirm = true
        case .needsPurchase:
            pendingKind = kind
            pendingAction = action
            pendingRecheck = recheck
            isPresentingPaywall = true
        }
    }

    func confirmUseCredit(userID: String, entitlementService: EntitlementServicing) async {
        guard let kind = pendingKind, let action = pendingAction else { return }
        isPresentingConfirm = false
        isBusy = true
        defer { isBusy = false }
        await redeemAndRun(kind: kind, action: action, userID: userID, entitlementService: entitlementService)
    }

    /// Called once a purchase made specifically to unblock the pending
    /// action reports success. The grant itself happens server-side (a
    /// Cloud Function reacting to the purchase claim doc), so it may not
    /// be reflected in the entitlement yet — this polls briefly rather
    /// than assuming it already landed. On timeout it just leaves the
    /// action pending for the user's next manual attempt: the credit
    /// they bought doesn't expire, so nothing is lost by waiting.
    func handlePurchaseSucceeded(userID: String, entitlementService: EntitlementServicing) async {
        isPresentingPaywall = false
        guard let kind = pendingKind, let action = pendingAction, let recheck = pendingRecheck else { return }
        isBusy = true
        defer { isBusy = false }

        let maxAttempts = 8
        for attemptIndex in 0..<maxAttempts {
            let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
            switch recheck(entitlement) {
            case .exempt:
                await action()
                return
            case .needsConfirmation:
                // Already paid specifically for this — spend the credit
                // automatically instead of asking again.
                await redeemAndRun(kind: kind, action: action, userID: userID, entitlementService: entitlementService)
                return
            case .needsPurchase:
                if attemptIndex < maxAttempts - 1 {
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }
        errorMessage = "Your purchase went through, but it's still applying — this can take a few moments. Your credit won't expire; just try again shortly."
    }

    private func redeemAndRun(
        kind: Kind,
        action: () async -> Void,
        userID: String,
        entitlementService: EntitlementServicing
    ) async {
        switch kind {
        case .groupCreation:
            // tier2Credits is spent atomically inside createGroup itself —
            // nothing to redeem separately first.
            await action()
        case .groupJoin:
            do {
                let redeemed = try await entitlementService.redeemTier1CreditForProUser(userID: userID)
                guard redeemed else {
                    errorMessage = "That credit isn't available anymore."
                    return
                }
                await action()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        isPresentingConfirm = false
        pendingKind = nil
        pendingAction = nil
        pendingRecheck = nil
    }
}

extension View {
    /// Attaches the confirm dialog, purchase sheet, and error alert that
    /// `EntitlementGateCoordinator` drives. Attach once per view that calls
    /// `coordinator.attempt(...)`.
    func entitlementGate(
        _ coordinator: EntitlementGateCoordinator,
        userID: String,
        entitlementService: EntitlementServicing,
        purchaseService: PurchaseServicing,
        claimWriter: PurchaseClaimSubmitting
    ) -> some View {
        self
            .confirmationDialog(
                "Use a Credit?",
                isPresented: Binding(
                    get: { coordinator.isPresentingConfirm },
                    set: { coordinator.isPresentingConfirm = $0 }
                ),
                titleVisibility: .visible
            ) {
                Button("Use Credit") {
                    Task { await coordinator.confirmUseCredit(userID: userID, entitlementService: entitlementService) }
                }
                Button("Cancel", role: .cancel) {
                    coordinator.cancel()
                }
            } message: {
                Text(coordinator.confirmMessage)
            }
            .sheet(isPresented: Binding(
                get: { coordinator.isPresentingPaywall },
                set: { coordinator.isPresentingPaywall = $0 }
            )) {
                MembershipPaywallView(
                    userID: userID,
                    purchaseService: purchaseService,
                    claimWriter: claimWriter,
                    entitlementService: entitlementService,
                    onPurchaseSucceeded: {
                        await coordinator.handlePurchaseSucceeded(userID: userID, entitlementService: entitlementService)
                    }
                )
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { coordinator.errorMessage != nil },
                    set: { if !$0 { coordinator.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(coordinator.errorMessage ?? "")
            }
    }
}
