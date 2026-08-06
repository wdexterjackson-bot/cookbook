//
//  EntitlementServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct EntitlementServicingTests {

    @Test func availableCreationCreditsReflectsStoredEntitlement() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice",
            creationCredits: 3,
            hasFamilyUser: true,
            familyUserPromoCreditAvailable: false,
            grantedPromoCredits: true,
            createdAt: .now
        )

        #expect(try await service.availableCreationCredits(userID: "alice") == 3)
        #expect(try await service.hasFamilyUser(userID: "alice") == true)
    }

    @Test func missingEntitlementDefaultsToZeroCreditsAndNoFamilyUser() async throws {
        let service = InMemoryEntitlementService()

        #expect(try await service.availableCreationCredits(userID: "nobody") == 0)
        #expect(try await service.hasFamilyUser(userID: "nobody") == false)
    }

    @Test func redeemFamilyUserPromoCreditFlipsBothFieldsWhenAvailable() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice",
            creationCredits: 3,
            hasFamilyUser: false,
            familyUserPromoCreditAvailable: true,
            grantedPromoCredits: true,
            createdAt: .now
        )

        let redeemed = try await service.redeemFamilyUserPromoCredit(userID: "alice")

        #expect(redeemed)
        #expect(try await service.hasFamilyUser(userID: "alice") == true)
        #expect(service.entitlementsByUserID["alice"]?.familyUserPromoCreditAvailable == false)
        #expect(service.entitlementsByUserID["alice"]?.creationCredits == 3)
    }

    @Test func redeemFamilyUserPromoCreditFailsWhenAlreadyRedeemedOrMissing() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice",
            creationCredits: 3,
            hasFamilyUser: false,
            familyUserPromoCreditAvailable: false,
            grantedPromoCredits: true,
            createdAt: .now
        )

        #expect(try await service.redeemFamilyUserPromoCredit(userID: "alice") == false)
        #expect(try await service.redeemFamilyUserPromoCredit(userID: "nobody") == false)
    }
}
