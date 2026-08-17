//
//  EntitlementGate.swift
//  cookbook
//
//  Shared paywall gate for the two actions that cost a credit: creating a
//  group/Family Cookbook (tier 2) and joining/connecting to one as a
//  non-MFB cookbook (tier 1, i.e. becoming a Pro User). Every call site
//  follows the same flow: already covered (MFB group, or already Pro) runs
//  the action immediately; a spendable credit shows a yes/no confirm before
//  spending it; no credit presents the purchase sheet instead. A purchase
//  doesn't auto-resume the original action — the sheet just dismisses, and
//  the user retries the same button, which by then either succeeds outright
//  (Pro) or re-evaluates against the freshly bought credit.
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
        if entitlement?.isProUser == true { return .exempt }
        if entitlement?.isActiveAnnualProMember == true { return .exempt }
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

    var confirmMessage: String {
        switch pendingKind {
        case .groupCreation:
            let n = confirmCreditsAvailable
            return "Use one of your \(n) Family Cookbook creation credit\(n == 1 ? "" : "s") to create this cookbook?"
        case .groupJoin:
            return "Use your free Pro User credit to connect with this family/friends' cookbook?"
        case nil:
            return ""
        }
    }

    /// Runs `action` directly if this action is exempt from the gate;
    /// otherwise shows the confirm-or-purchase UI and `action` only runs
    /// once the user confirms spending a credit.
    func attempt(
        _ kind: Kind,
        outcome: EntitlementGateOutcome,
        action: @escaping () async -> Void
    ) async {
        errorMessage = nil
        switch outcome {
        case .exempt:
            await action()
        case .needsConfirmation(let credits):
            pendingKind = kind
            pendingAction = action
            confirmCreditsAvailable = credits
            isPresentingConfirm = true
        case .needsPurchase:
            pendingKind = kind
            pendingAction = nil
            isPresentingPaywall = true
        }
    }

    func confirmUseCredit(userID: String, entitlementService: EntitlementServicing) async {
        guard let kind = pendingKind, let action = pendingAction else { return }
        isPresentingConfirm = false
        isBusy = true
        defer { isBusy = false }

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
                    entitlementService: entitlementService
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
