//
//  EntitlementGranting.swift
//  cookbook
//
//  The seam for the one Firestore write the client is allowed to make to
//  its own entitlement document without a Cloud Function: backfilling the
//  free launch credits (1 tier-1 Pro-User credit, 2 tier-2 group-creation
//  credits) it's entitled to but hasn't received yet. Called unconditionally
//  on every app launch (see AuthGatedRootView) — already-received credits
//  are never re-granted, even once spent down to zero.
//

import Foundation

protocol EntitlementGranting {
    /// Grants whichever of the two free launch credits `userID` hasn't
    /// received yet and is still within its own expiration window (each
    /// tier is independent — see LaunchCreditPromo). Safe to call on every
    /// launch/sign-in — a no-op once both have been granted, or once both
    /// windows have passed.
    func grantMissingLaunchCreditsIfEligible(userID: String, now: Date) async throws
}

extension EntitlementGranting {
    func grantMissingLaunchCreditsIfEligible(userID: String) async throws {
        try await grantMissingLaunchCreditsIfEligible(userID: userID, now: .now)
    }
}

enum LaunchCreditPromo {
    /// Spent to become a Pro User (join/publish to unlimited group cookbooks).
    static let tier1CreditCount = 1
    /// Spent to create a group/Family Cookbook.
    static let tier2CreditCount = 2

    /// Pro User (tier1) free credits are grantable to new accounts, and
    /// usable once granted, only until this date — the same value serves
    /// both purposes deliberately (confirmed decision: an unspent credit
    /// itself expires, not just the grant window for new signups; granting
    /// a credit that would already be expired makes no sense).
    static let tier1ExpirationDate = makeUTCDate(year: 2027, month: 1, day: 1)
    /// Family Cookbook (tier2) free credits — same reasoning, later date.
    static let tier2ExpirationDate = makeUTCDate(year: 2029, month: 1, day: 1)

    static func isTier1Eligible(on date: Date) -> Bool {
        date < tier1ExpirationDate
    }
    static func isTier2Eligible(on date: Date) -> Bool {
        date < tier2ExpirationDate
    }
    /// Coarse "is the promo active at all" check, true as long as at least
    /// one tier could still be granted — for callers that don't model the
    /// two tiers independently (e.g. FakeEntitlementGranter).
    static func isAnyTierEligible(on date: Date) -> Bool {
        date < tier2ExpirationDate
    }

    private static func makeUTCDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)!
    }
}
