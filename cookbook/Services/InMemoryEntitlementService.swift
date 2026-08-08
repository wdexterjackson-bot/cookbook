//
//  InMemoryEntitlementService.swift
//  cookbook
//

import Foundation

final class InMemoryEntitlementService: EntitlementServicing {
    var entitlementsByUserID: [String: Entitlement] = [:]

    func fetchEntitlement(userID: String) async throws -> Entitlement? {
        entitlementsByUserID[userID]
    }

    @discardableResult
    func redeemTier1CreditForProUser(userID: String) async throws -> Bool {
        guard var entitlement = entitlementsByUserID[userID],
              entitlement.tier1Credits > 0,
              !entitlement.isProUser
        else {
            return false
        }

        entitlement.tier1Credits -= 1
        entitlement.isProUser = true
        entitlementsByUserID[userID] = entitlement
        return true
    }

    func deleteEntitlement(userID: String) async throws {
        entitlementsByUserID.removeValue(forKey: userID)
    }
}
