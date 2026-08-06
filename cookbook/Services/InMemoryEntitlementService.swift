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
    func redeemFamilyUserPromoCredit(userID: String) async throws -> Bool {
        guard var entitlement = entitlementsByUserID[userID],
              entitlement.familyUserPromoCreditAvailable,
              !entitlement.hasFamilyUser
        else {
            return false
        }

        entitlement.familyUserPromoCreditAvailable = false
        entitlement.hasFamilyUser = true
        entitlementsByUserID[userID] = entitlement
        return true
    }
}
