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
    /// received yet, but only while `LaunchCreditPromo.isEligible(on: now)`.
    /// Safe to call on every launch/sign-in — a no-op once both have been
    /// granted once.
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

    static let cutoffDate: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var components = DateComponents()
        components.year = 2029
        components.month = 1
        components.day = 1
        return calendar.date(from: components)!
    }()

    static func isEligible(on date: Date) -> Bool {
        date < cutoffDate
    }
}
