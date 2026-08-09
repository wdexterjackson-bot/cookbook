//
//  FakeEntitlementGranter.swift
//  cookbook
//

import Foundation

final class FakeEntitlementGranter: EntitlementGranting {
    private(set) var grantedUserIDs: [String] = []

    func grantMissingLaunchCreditsIfEligible(userID: String, now: Date) async throws {
        guard LaunchCreditPromo.isAnyTierEligible(on: now) else { return }
        guard !grantedUserIDs.contains(userID) else { return }
        grantedUserIDs.append(userID)
    }
}
