//
//  PurchaseCoordinator.swift
//  cookbook
//

import Foundation

/// The purchase→claim-submission sequence MembershipPaywallView drives —
/// extracted so it's testable without SwiftUI, same reasoning as
/// RecipePublishingCoordinator/PostSignInCoordinator. Enforces the one
/// invariant that actually matters here: a claim is submitted if, and only
/// if, StoreKit reports a genuine `.success` outcome — `.pending` and
/// `.userCancelled` must never produce a claim, and neither should this
/// function ever write an entitlement directly (see PurchaseServicing.swift
/// for why that's a Cloud Function's job, not the client's).
enum PurchaseCoordinator {
    @discardableResult
    static func purchase(
        _ product: PurchasableProduct,
        userID: String,
        purchaseService: PurchaseServicing,
        claimWriter: PurchaseClaimSubmitting
    ) async throws -> PurchaseOutcome {
        let outcome = try await purchaseService.purchase(productID: product.id)
        if case .success(let receipt) = outcome {
            do {
                try await claimWriter.submit(receipt, userID: userID)
            } catch {
                // Apple has already been paid — the transaction is left
                // unfinished (StoreKitPurchaseService.purchase() never
                // calls finish() itself) so reconcileUnfinishedTransactions
                // can catch it up on a future launch or purchase attempt.
                // Thrown as a distinct error rather than the raw one so the
                // UI can say "this will resolve automatically" instead of
                // implying the purchase itself didn't go through.
                throw PurchaseServiceError.claimSubmissionFailed
            }
            await purchaseService.finishTransaction(transactionID: receipt.transactionID)
        }
        return outcome
    }

    /// Catches up on transactions StoreKit confirmed but this device never
    /// finished — the case `purchase(_:userID:purchaseService:claimWriter:)`
    /// above now leaves behind when claim submission fails. Run once at
    /// launch (AuthGatedRootView) alongside the existing launch-credit
    /// grant. Best-effort per transaction: one still-unresolvable claim
    /// shouldn't block reconciling the others.
    static func reconcileUnfinishedTransactions(
        userID: String,
        purchaseService: PurchaseServicing,
        claimWriter: PurchaseClaimSubmitting
    ) async {
        for receipt in await purchaseService.unfinishedReceipts() {
            do {
                try await claimWriter.submit(receipt, userID: userID)
                await purchaseService.finishTransaction(transactionID: receipt.transactionID)
            } catch {
                continue
            }
        }
    }
}
