//
//  EntitlementGranting.swift
//  cookbook
//
//  The seam for the one Firestore write Milestone 2A needs: granting the
//  promo group-creation credits on brand-new accounts. The full Entitlement
//  data model + EntitlementServicing seam (purchases, restore, etc.) lands
//  in Milestone 2D — this stays deliberately narrow until then.
//

import Foundation

protocol EntitlementGranting {
    /// Grants the sign-up promo (3 free group-creation credits) if `now` is
    /// before the promo cutoff and this user hasn't already been granted
    /// credits. Safe to call unconditionally on every account creation.
    func grantPromoCreditsIfEligible(userID: String, now: Date) async throws
}

extension EntitlementGranting {
    func grantPromoCreditsIfEligible(userID: String) async throws {
        try await grantPromoCreditsIfEligible(userID: userID, now: .now)
    }
}

enum PromoCredit {
    static let creditCount = 3
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
