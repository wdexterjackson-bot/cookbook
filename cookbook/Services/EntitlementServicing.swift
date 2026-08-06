//
//  EntitlementServicing.swift
//  cookbook
//
//  Read/query side of entitlements/{uid}. Granting promo credits stays in
//  EntitlementGranting (Milestone 2A); StoreKit purchase flow and applying
//  a purchase to this same document is Milestone 2D. createGroup's credit
//  consumption (GroupsServicing) reads/writes this document directly in
//  its own transaction rather than going through this protocol, since that
//  write has to be atomic with the group/membership writes.
//
//  redeemFamilyUserPromoCredit is the one exception to "read-only protocol":
//  unlike a StoreKit purchase (which must be granted server-side, see
//  PurchaseClaimWriter), the free promo credit is already sitting on the
//  user's own entitlement document, so flipping it to hasFamilyUser is a
//  same-document, same-owner write that firestore.rules can verify entirely
//  on its own (paired-transition check, no external signature needed).
//

import Foundation

protocol EntitlementServicing {
    func fetchEntitlement(userID: String) async throws -> Entitlement?
    func hasFamilyUser(userID: String) async throws -> Bool
    func availableCreationCredits(userID: String) async throws -> Int

    /// Redeems the free Family User promo credit, if one is available and
    /// unredeemed. Returns false (no throw) when there's nothing to redeem —
    /// callers use this to distinguish "already handled" from "went wrong."
    @discardableResult
    func redeemFamilyUserPromoCredit(userID: String) async throws -> Bool

    /// Account deletion cleanup — best-effort by design (callers should
    /// treat failure here as non-fatal, same as Storage cleanup elsewhere).
    func deleteEntitlement(userID: String) async throws
}

extension EntitlementServicing {
    func hasFamilyUser(userID: String) async throws -> Bool {
        try await fetchEntitlement(userID: userID)?.hasFamilyUser ?? false
    }

    func availableCreationCredits(userID: String) async throws -> Int {
        try await fetchEntitlement(userID: userID)?.creationCredits ?? 0
    }
}
