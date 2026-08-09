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
            try await claimWriter.submit(receipt, userID: userID)
        }
        return outcome
    }
}
