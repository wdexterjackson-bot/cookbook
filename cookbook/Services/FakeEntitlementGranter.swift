//
//  FakeEntitlementGranter.swift
//  cookbook
//

import Foundation

final class FakeEntitlementGranter: EntitlementGranting {
    private(set) var grantedUserIDs: [String] = []

    func grantPromoCreditsIfEligible(userID: String, now: Date) async throws {
        guard PromoCredit.isEligible(on: now) else { return }
        guard !grantedUserIDs.contains(userID) else { return }
        grantedUserIDs.append(userID)
    }
}
