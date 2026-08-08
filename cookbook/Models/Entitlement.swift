//
//  Entitlement.swift
//  cookbook
//
//  Two independent credit tiers (PRD paywall rework, Aug 2026):
//  - Tier 1 credits are spent to become a Pro User (join/publish to
//    unlimited group cookbooks). One-time $0.99 purchase once credits run out.
//  - Tier 2 credits are spent to create a group/Family Cookbook. $1.99 per
//    additional one once credits run out.
//  `receivedTier1PromoCredit`/`receivedTier2PromoCredits` are separate from
//  the credit counts themselves — they track "has this account ever been
//  granted its free launch credit," so a launch-time backfill (see
//  EntitlementGranting) can top up whichever one is still missing without
//  re-granting one the account already received and has since spent.
//

import Foundation

struct Entitlement: Decodable, Equatable {
    var userID: String
    var tier1Credits: Int
    var tier2Credits: Int
    var isProUser: Bool
    var receivedTier1PromoCredit: Bool
    var receivedTier2PromoCredits: Bool
    var createdAt: Date

    init(
        userID: String,
        tier1Credits: Int,
        tier2Credits: Int,
        isProUser: Bool,
        receivedTier1PromoCredit: Bool,
        receivedTier2PromoCredits: Bool,
        createdAt: Date
    ) {
        self.userID = userID
        self.tier1Credits = tier1Credits
        self.tier2Credits = tier2Credits
        self.isProUser = isProUser
        self.receivedTier1PromoCredit = receivedTier1PromoCredit
        self.receivedTier2PromoCredits = receivedTier2PromoCredits
        self.createdAt = createdAt
    }

    /// Tolerant of documents written under the single-tier scheme this
    /// replaces (`creationCredits`/`hasFamilyUser`/
    /// `familyUserPromoCreditAvailable`/`grantedPromoCredits`) — an
    /// old-shaped doc decodes as "hasn't received either free credit yet"
    /// (so the launch-time backfill tops it up) while preserving whatever
    /// balance/status it already had, rather than throwing or silently
    /// discarding it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        if let tier1Credits = try container.decodeIfPresent(Int.self, forKey: .tier1Credits) {
            self.tier1Credits = tier1Credits
            receivedTier1PromoCredit = try container.decodeIfPresent(Bool.self, forKey: .receivedTier1PromoCredit) ?? false
            isProUser = try container.decodeIfPresent(Bool.self, forKey: .isProUser) ?? false
        } else {
            // Legacy doc: an unredeemed familyUserPromoCreditAvailable flag
            // *is* an unspent tier-1 credit; hasFamilyUser already redeemed
            // means it was already spent.
            let legacyPromoAvailable = try container.decodeIfPresent(Bool.self, forKey: .legacyFamilyUserPromoCreditAvailable) ?? false
            let legacyHasFamilyUser = try container.decodeIfPresent(Bool.self, forKey: .legacyHasFamilyUser) ?? false
            tier1Credits = legacyPromoAvailable ? 1 : 0
            receivedTier1PromoCredit = legacyPromoAvailable || legacyHasFamilyUser
            isProUser = legacyHasFamilyUser
        }

        if let tier2Credits = try container.decodeIfPresent(Int.self, forKey: .tier2Credits) {
            self.tier2Credits = tier2Credits
            receivedTier2PromoCredits = try container.decodeIfPresent(Bool.self, forKey: .receivedTier2PromoCredits) ?? false
        } else {
            tier2Credits = try container.decodeIfPresent(Int.self, forKey: .legacyCreationCredits) ?? 0
            receivedTier2PromoCredits = try container.decodeIfPresent(Bool.self, forKey: .legacyGrantedPromoCredits) ?? false
        }
    }

    private enum CodingKeys: String, CodingKey {
        case userID, tier1Credits, tier2Credits, isProUser
        case receivedTier1PromoCredit, receivedTier2PromoCredits, createdAt
        case legacyCreationCredits = "creationCredits"
        case legacyHasFamilyUser = "hasFamilyUser"
        case legacyFamilyUserPromoCreditAvailable = "familyUserPromoCreditAvailable"
        case legacyGrantedPromoCredits = "grantedPromoCredits"
    }
}
