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
        if let expiresAt = entitlement.tier1ExpiresAt, expiresAt < .now {
            throw EntitlementServiceError.creditExpired
        }

        entitlement.tier1Credits -= 1
        entitlement.isProUser = true
        entitlementsByUserID[userID] = entitlement
        return true
    }

    func applyDiscountCode(_ code: String, userID: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard DiscountCodePromo.isValid(trimmed) else {
            throw EntitlementServiceError.invalidDiscountCode
        }
        guard var entitlement = entitlementsByUserID[userID] else { return }
        guard !entitlement.redeemedDiscountCodes.contains(trimmed) else {
            throw EntitlementServiceError.discountCodeAlreadyRedeemed
        }
        entitlement.redeemedDiscountCodes.append(trimmed)
        entitlement.annualProMembershipCredits += 1
        entitlementsByUserID[userID] = entitlement
    }

    @discardableResult
    func redeemAnnualProMembershipCredit(userID: String) async throws -> Bool {
        guard var entitlement = entitlementsByUserID[userID], entitlement.annualProMembershipCredits > 0 else {
            return false
        }
        entitlement.annualProMembershipCredits -= 1
        entitlement.annualProMembershipExpiresAt = Date.now.addingTimeInterval(365 * 24 * 60 * 60)
        entitlementsByUserID[userID] = entitlement
        return true
    }

    func deleteEntitlement(userID: String) async throws {
        entitlementsByUserID.removeValue(forKey: userID)
    }
}
