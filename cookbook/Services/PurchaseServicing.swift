//
//  PurchaseServicing.swift
//  cookbook
//
//  The seam for StoreKit: StoreKitPurchaseService is the real adapter,
//  FakePurchaseService backs tests. Wraps StoreKit's Product/Transaction in
//  plain DTOs so the fake doesn't need to import StoreKit at all, matching
//  every other seam in this codebase.
//
//  Deliberately does NOT write the entitlement itself — per firestore.rules
//  (milestone 2C), a client can only ever *spend* a credit (decrement by
//  exactly 1), never grant itself one. A successful purchase here produces
//  a PurchaseReceipt that the caller submits as a purchaseClaims doc
//  (PurchaseClaimWriter) for a Cloud Function to verify and apply
//  server-side.
//

import Foundation

enum StoreProductID {
    /// One-time purchase that redeems as a tier-1 credit spent immediately
    /// toward Pro User — the underlying StoreKit product ID string is kept
    /// as-is (renaming would mean a new App Store Connect product) even
    /// though the Swift-side name and its Pro User branding are new.
    static let proUserLifetime = "VibeApp.cookbook.familyUser.lifetime"
    /// One-time purchase that redeems as one tier-2 (Family Cookbook
    /// creation) credit. Same "product ID string unchanged" reasoning.
    static let familyCookbookCredit = "VibeApp.cookbook.groupCreationCredit"
    /// Auto-renewing yearly subscription — an alternative path to the same
    /// group-join/publish access `proUserLifetime` grants, for members who
    /// prefer year-to-year billing over a lifetime purchase. See
    /// Entitlement.isActiveAnnualProMember for how this is checked.
    static let annualProMembership = "VibeApp.cookbook.annualProMembership"

    static let all = [proUserLifetime, familyCookbookCredit, annualProMembership]
}

enum PurchaseKind: Equatable {
    case nonConsumable
    case consumable
    case autoRenewable
}

struct PurchasableProduct: Identifiable, Equatable {
    var id: String
    var displayName: String
    var description: String
    var displayPrice: String
    var kind: PurchaseKind
}

/// What a Cloud Function needs to independently verify the purchase really
/// happened — the signed JWS, not just "trust me."
struct PurchaseReceipt: Equatable {
    var transactionID: String
    var productID: String
    var jwsRepresentation: String
}

enum PurchaseOutcome: Equatable {
    case success(PurchaseReceipt)
    case pending
    case userCancelled
}

enum PurchaseServiceError: Error, Equatable {
    case productNotFound
    case verificationFailed
    /// StoreKit confirmed the purchase (Apple has been paid) but submitting
    /// the purchaseClaims doc failed — distinct from every other error here
    /// so the UI can say "this will resolve automatically" instead of
    /// implying the purchase itself didn't go through. The transaction is
    /// deliberately left unfinished when this is thrown (see
    /// PurchaseCoordinator.purchase) so PurchaseCoordinator.
    /// reconcileUnfinishedTransactions can catch it up later.
    case claimSubmissionFailed
}

protocol PurchaseServicing {
    func fetchProducts() async throws -> [PurchasableProduct]
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restorePurchases() async throws
    /// Verified (StoreKit-signature-checked), currently-active entitlement
    /// product IDs — the non-consumable Family User purchase shows up here
    /// forever; consumables never do (they're spent, not "entitled").
    func currentEntitlementProductIDs() async -> Set<String>
    /// Same population as `currentEntitlementProductIDs`, but as full
    /// receipts a claim can actually be resubmitted from — used by "Restore
    /// Purchases" to recover a purchase StoreKit still shows as owned (this
    /// device or another, via Family Sharing) that the server's entitlement
    /// doc doesn't yet reflect. Safe to resubmit unconditionally, even for
    /// an already-applied purchase: applyPurchaseClaim.js is keyed by
    /// transaction ID and no-ops on a repeat.
    func currentEntitlementReceipts() async -> [PurchaseReceipt]
    /// Transactions StoreKit confirmed but this device never finished —
    /// the case where `purchase(productID:)` returned `.success` but the
    /// caller's claim submission never completed (offline, app killed).
    /// Resubmitting+finishing these is what PurchaseCoordinator.
    /// reconcileUnfinishedTransactions does at launch.
    func unfinishedReceipts() async -> [PurchaseReceipt]
    /// Marks a transaction fully processed — StoreKit will never redeliver
    /// it via `unfinishedReceipts`/`Transaction.updates` again. Only call
    /// this once its purchaseClaims doc has actually been submitted.
    func finishTransaction(transactionID: String) async
}
