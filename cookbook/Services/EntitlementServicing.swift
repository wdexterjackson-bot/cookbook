//
//  EntitlementServicing.swift
//  cookbook
//
//  Read/query side of entitlements/{uid}. Granting free launch credits stays
//  in EntitlementGranting; StoreKit purchase flow and applying a purchase to
//  this same document happens server-side via a Cloud Function (see
//  PurchaseClaimWriter). createGroup's tier2Credits consumption
//  (GroupsServicing) reads/writes this document directly in its own
//  transaction rather than going through this protocol, since that write
//  has to be atomic with the group/membership writes.
//
//  redeemTier1CreditForProUser is the one exception to "read-only protocol":
//  unlike a StoreKit purchase (which must be granted server-side, see
//  PurchaseClaimWriter), a tier-1 credit already sitting on the user's own
//  entitlement document is theirs to spend, so decrementing it and flipping
//  isProUser together is a same-document, same-owner write that
//  firestore.rules can verify entirely on its own (a paired-transition
//  check, no external signature needed).
//

import Foundation

enum EntitlementServiceError: Error, Equatable {
    /// The account has a tier-1 credit on paper, but it's past
    /// `Entitlement.tier1ExpiresAt` — thrown by a client-side pre-check so
    /// this surfaces as a clean, catchable error instead of an opaque
    /// Firestore permission-denied from the rules-side enforcement.
    case creditExpired
    /// The entered code doesn't match any currently-valid discount code —
    /// checked client-side first for a clean, specific error message; the
    /// code itself and its deadline are also enforced in firestore.rules,
    /// which is the real authorization (a client-side check alone could be
    /// bypassed by a modified client).
    case invalidDiscountCode
    /// This account has already redeemed this exact code before.
    case discountCodeAlreadyRedeemed
}

protocol EntitlementServicing {
    func fetchEntitlement(userID: String) async throws -> Entitlement?
    func isProUser(userID: String) async throws -> Bool
    func availableTier1Credits(userID: String) async throws -> Int
    func availableTier2Credits(userID: String) async throws -> Int

    /// Spends one tier-1 credit to become a Pro User, if one is available
    /// and the account isn't already Pro. Returns false (no throw) when
    /// there's nothing to redeem — callers use this to distinguish
    /// "already handled" from "went wrong."
    @discardableResult
    func redeemTier1CreditForProUser(userID: String) async throws -> Bool

    /// Validates and applies a discount code, granting one Annual Pro
    /// Membership credit on success. Throws EntitlementServiceError for an
    /// unknown or already-used code rather than returning a bool — unlike
    /// the credit-spend methods below, "which specific reason" matters
    /// here for the message shown next to the input field.
    func applyDiscountCode(_ code: String, userID: String) async throws

    /// Spends one Annual Pro Membership credit, activating (or extending
    /// — see the implementation's own note on this) the membership for one
    /// year from the moment this is called. Returns false (no throw) when
    /// there's no credit available to spend.
    @discardableResult
    func redeemAnnualProMembershipCredit(userID: String) async throws -> Bool

    /// Account deletion cleanup — best-effort by design (callers should
    /// treat failure here as non-fatal, same as Storage cleanup elsewhere).
    func deleteEntitlement(userID: String) async throws
}

extension EntitlementServicing {
    func isProUser(userID: String) async throws -> Bool {
        try await fetchEntitlement(userID: userID)?.isEffectivelyProUser ?? false
    }

    func availableTier1Credits(userID: String) async throws -> Int {
        try await fetchEntitlement(userID: userID)?.tier1Credits ?? 0
    }

    func availableTier2Credits(userID: String) async throws -> Int {
        try await fetchEntitlement(userID: userID)?.tier2Credits ?? 0
    }
}
