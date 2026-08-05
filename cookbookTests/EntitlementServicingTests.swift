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
}
