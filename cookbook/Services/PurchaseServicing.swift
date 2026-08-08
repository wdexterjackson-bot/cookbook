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

    static let all = [proUserLifetime, familyCookbookCredit]
}

enum PurchaseKind: Equatable {
    case nonConsumable
    case consumable
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
}

protocol PurchaseServicing {
    func fetchProducts() async throws -> [PurchasableProduct]
    func purchase(productID: String) async throws -> PurchaseOutcome
    func restorePurchases() async throws
    /// Verified (StoreKit-signature-checked), currently-active entitlement
    /// product IDs — the non-consumable Family User purchase shows up here
    /// forever; consumables never do (they're spent, not "entitled").
    func currentEntitlementProductIDs() async -> Set<String>
}
