//
//  Entitlement.swift
//  cookbook
//

import Foundation

struct Entitlement: Codable, Equatable {
    var userID: String
    var creationCredits: Int
    var hasFamilyUser: Bool
    /// A one-time free Family User upgrade granted alongside the sign-up
    /// promo credits (pre-2029 accounts only). Distinct from
    /// `creationCredits`: it isn't spent by creating a group, only by
    /// redeeming it for `hasFamilyUser`. It never expires and is never
    /// transferable — it lives on this account until redeemed.
    var familyUserPromoCreditAvailable: Bool
    var grantedPromoCredits: Bool
    var createdAt: Date
}
