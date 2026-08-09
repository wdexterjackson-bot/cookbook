//
//  EntitlementGrantingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct EntitlementGrantingTests {

    @Test func tier1IsEligibleBeforeItsOwnCutoff() {
        let beforeCutoff = ISO8601DateFormatter().date(from: "2026-01-01T00:00:00Z")!
        #expect(LaunchCreditPromo.isTier1Eligible(on: beforeCutoff))
    }

    @Test func tier1IsNotEligibleAfterItsOwnCutoff() {
        let afterCutoff = ISO8601DateFormatter().date(from: "2027-06-01T00:00:00Z")!
        #expect(!LaunchCreditPromo.isTier1Eligible(on: afterCutoff))
    }

    @Test func tier2IsEligibleBeforeItsOwnCutoff() {
        let beforeCutoff = ISO8601DateFormatter().date(from: "2028-01-01T00:00:00Z")!
        #expect(LaunchCreditPromo.isTier2Eligible(on: beforeCutoff))
    }

    @Test func tier2IsNotEligibleAfterItsOwnCutoff() {
        let afterCutoff = ISO8601DateFormatter().date(from: "2029-06-01T00:00:00Z")!
        #expect(!LaunchCreditPromo.isTier2Eligible(on: afterCutoff))
    }

    /// Between the two cutoffs, tier1 has expired but tier2 hasn't —
    /// confirms the tiers are gated independently, not by one shared date.
    @Test func tier1ExpiresBeforeTier2() {
        let betweenCutoffs = ISO8601DateFormatter().date(from: "2028-01-01T00:00:00Z")!
        #expect(!LaunchCreditPromo.isTier1Eligible(on: betweenCutoffs))
        #expect(LaunchCreditPromo.isTier2Eligible(on: betweenCutoffs))
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
