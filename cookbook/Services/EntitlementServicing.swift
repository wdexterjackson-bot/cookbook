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

    /// Account deletion cleanup — best-effort by design (callers should
    /// treat failure here as non-fatal, same as Storage cleanup elsewhere).
    func deleteEntitlement(userID: String) async throws
}

extension EntitlementServicing {
    func isProUser(userID: String) async throws -> Bool {
        try await fetchEntitlement(userID: userID)?.isProUser ?? false
    }

    func availableTier1Credits(userID: String) async throws -> Int {
        try await fetchEntitlement(userID: userID)?.tier1Credits ?? 0
    }

    func availableTier2Credits(userID: String) async throws -> Int {
        try await fetchEntitlement(userID: userID)?.tier2Credits ?? 0
    }
}
