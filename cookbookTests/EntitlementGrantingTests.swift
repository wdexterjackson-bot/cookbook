//
//  EntitlementGrantingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct EntitlementGrantingTests {

    @Test func promoIsEligibleBeforeCutoff() {
        let beforeCutoff = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        #expect(LaunchCreditPromo.isEligible(on: beforeCutoff))
    }

    @Test func promoIsNotEligibleAfterCutoff() {
        let afterCutoff = ISO8601DateFormatter().date(from: "2029-06-01T00:00:00Z")!
        #expect(!LaunchCreditPromo.isEligible(on: afterCutoff))
    }

    @Test func fakeGranterGrantsOncePerUser() async throws {
        let granter = FakeEntitlementGranter()
        let eligibleDate = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!

        try await granter.grantMissingLaunchCreditsIfEligible(userID: "uid-1", now: eligibleDate)
        try await granter.grantMissingLaunchCreditsIfEligible(userID: "uid-1", now: eligibleDate)

        #expect(granter.grantedUserIDs == ["uid-1"])
    }

    @Test func fakeGranterSkipsIneligibleDates() async throws {
        let granter = FakeEntitlementGranter()
        let ineligibleDate = ISO8601DateFormatter().date(from: "2030-01-01T00:00:00Z")!

        try await granter.grantMissingLaunchCreditsIfEligible(userID: "uid-1", now: ineligibleDate)

        #expect(granter.grantedUserIDs.isEmpty)
    }
}
