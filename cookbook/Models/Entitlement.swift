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
    /// Set once, at grant time, only for the free launch-promo credits
    /// (see LaunchCreditPromo) — nil for a paid purchase (those never
    /// expire, confirmed decision) and nil for docs that predate this
    /// field. A non-nil, past date here means an unspent credit is no
    /// longer usable, checked both client-side (for a clean error) and in
    /// firestore.rules (the actual enforcement).
    var tier1ExpiresAt: Date?
    var tier2ExpiresAt: Date?
    /// Awarded-but-unused Annual Pro Membership credits — same shape as
    /// tier1Credits/tier2Credits (a count to spend, not a status), granted
    /// today only via a discount code (see redeemedDiscountCodes below).
    /// This is a stepping stone ahead of the full Annual Pro Member
    /// subscription build (StoreKit product, App Store Server
    /// Notifications, the 90-day photo-deletion sweep) — see the
    /// #4 implementation plan; a credit-granted membership sets
    /// annualProMembershipExpiresAt exactly the same as a future real
    /// purchase would, so the rest of the app never needs to know which
    /// path granted it.
    var annualProMembershipCredits: Int
    /// When the account's Annual Pro Membership is active through — nil
    /// means never activated. Whoever reads this to gate a feature should
    /// compare against .now, not just nil-check it.
    var annualProMembershipExpiresAt: Date?
    /// Exact discount code strings already applied to this account, kept
    /// so the same code can't be redeemed twice by the same user — the
    /// valid code(s) themselves and their deadline are enforced in
    /// firestore.rules, not just here.
    var redeemedDiscountCodes: [String]
    /// Set by the 90-day sweep once a lapsed member's cloud photos have
    /// been deleted — nil means either still active, still within the
    /// 90-day grace window, or never had photos removed. Cleared on
    /// re-subscribe so a future lapse sweeps again.
    var annualProMembershipImagesRemovedAt: Date?
    /// StoreKit's originalTransactionId for the current/most recent real
    /// subscription purchase — how appStoreServerNotifications resolves an
    /// incoming Apple notification back to this account. Nil for an
    /// account that has only ever redeemed a discount-code credit, never
    /// made a real purchase.
    var annualProMembershipOriginalTransactionID: String?
    /// Set from Apple's own gracePeriodExpiresDate while a renewal is
    /// failing but Apple is still retrying billing — the sweep must not
    /// treat the member as lapsed while this is still in the future, even
    /// past the normal 90-day mark.
    var annualProMembershipBillingRetryUntil: Date?
    /// Last-known autoRenewStatus from Apple — informational only, used to
    /// show a quiet "won't renew" badge while the membership is still
    /// otherwise active. Not used for any access decision.
    var annualProMembershipWillRenew: Bool?
    /// Dedup markers so the daily sweep's day-75/day-85 warning emails
    /// fire once each, not on every run while a lapsed member sits
    /// unswept.
    var annualProMembershipWarnedAtDay75: Bool?
    var annualProMembershipWarnedAtDay85: Bool?

    init(
        userID: String,
        tier1Credits: Int,
        tier2Credits: Int,
        isProUser: Bool,
        receivedTier1PromoCredit: Bool,
        receivedTier2PromoCredits: Bool,
        createdAt: Date,
        tier1ExpiresAt: Date? = nil,
        tier2ExpiresAt: Date? = nil,
        annualProMembershipCredits: Int = 0,
        annualProMembershipExpiresAt: Date? = nil,
        redeemedDiscountCodes: [String] = [],
        annualProMembershipImagesRemovedAt: Date? = nil,
        annualProMembershipOriginalTransactionID: String? = nil,
        annualProMembershipBillingRetryUntil: Date? = nil,
        annualProMembershipWillRenew: Bool? = nil,
        annualProMembershipWarnedAtDay75: Bool? = nil,
        annualProMembershipWarnedAtDay85: Bool? = nil
    ) {
        self.userID = userID
        self.tier1Credits = tier1Credits
        self.tier2Credits = tier2Credits
        self.isProUser = isProUser
        self.receivedTier1PromoCredit = receivedTier1PromoCredit
        self.receivedTier2PromoCredits = receivedTier2PromoCredits
        self.createdAt = createdAt
        self.tier1ExpiresAt = tier1ExpiresAt
        self.tier2ExpiresAt = tier2ExpiresAt
        self.annualProMembershipCredits = annualProMembershipCredits
        self.annualProMembershipExpiresAt = annualProMembershipExpiresAt
        self.redeemedDiscountCodes = redeemedDiscountCodes
        self.annualProMembershipImagesRemovedAt = annualProMembershipImagesRemovedAt
        self.annualProMembershipOriginalTransactionID = annualProMembershipOriginalTransactionID
        self.annualProMembershipBillingRetryUntil = annualProMembershipBillingRetryUntil
        self.annualProMembershipWillRenew = annualProMembershipWillRenew
        self.annualProMembershipWarnedAtDay75 = annualProMembershipWarnedAtDay75
        self.annualProMembershipWarnedAtDay85 = annualProMembershipWarnedAtDay85
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

        tier1ExpiresAt = try container.decodeIfPresent(Date.self, forKey: .tier1ExpiresAt)
        tier2ExpiresAt = try container.decodeIfPresent(Date.self, forKey: .tier2ExpiresAt)
        annualProMembershipCredits = try container.decodeIfPresent(Int.self, forKey: .annualProMembershipCredits) ?? 0
        annualProMembershipExpiresAt = try container.decodeIfPresent(Date.self, forKey: .annualProMembershipExpiresAt)
        redeemedDiscountCodes = try container.decodeIfPresent([String].self, forKey: .redeemedDiscountCodes) ?? []
        annualProMembershipImagesRemovedAt = try container.decodeIfPresent(Date.self, forKey: .annualProMembershipImagesRemovedAt)
        annualProMembershipOriginalTransactionID = try container.decodeIfPresent(String.self, forKey: .annualProMembershipOriginalTransactionID)
        annualProMembershipBillingRetryUntil = try container.decodeIfPresent(Date.self, forKey: .annualProMembershipBillingRetryUntil)
        annualProMembershipWillRenew = try container.decodeIfPresent(Bool.self, forKey: .annualProMembershipWillRenew)
        annualProMembershipWarnedAtDay75 = try container.decodeIfPresent(Bool.self, forKey: .annualProMembershipWarnedAtDay75)
        annualProMembershipWarnedAtDay85 = try container.decodeIfPresent(Bool.self, forKey: .annualProMembershipWarnedAtDay85)
    }

    /// True while a real purchase or a redeemed discount-code credit has
    /// this account's Annual Pro Membership active — the single source of
    /// truth every Pro-gated check should read instead of `isProUser`
    /// alone, so an active annual membership actually grants the access
    /// the redemption flow implies. See EntitlementGate.forGroupJoin.
    var isActiveAnnualProMember: Bool {
        (annualProMembershipExpiresAt ?? .distantPast) > .now
    }

    private enum CodingKeys: String, CodingKey {
        case userID, tier1Credits, tier2Credits, isProUser
        case receivedTier1PromoCredit, receivedTier2PromoCredits, createdAt
        case tier1ExpiresAt, tier2ExpiresAt
        case annualProMembershipCredits, annualProMembershipExpiresAt, redeemedDiscountCodes
        case annualProMembershipImagesRemovedAt, annualProMembershipOriginalTransactionID
        case annualProMembershipBillingRetryUntil, annualProMembershipWillRenew
        case annualProMembershipWarnedAtDay75, annualProMembershipWarnedAtDay85
        case legacyCreationCredits = "creationCredits"
        case legacyHasFamilyUser = "hasFamilyUser"
        case legacyFamilyUserPromoCreditAvailable = "familyUserPromoCreditAvailable"
        case legacyGrantedPromoCredits = "grantedPromoCredits"
    }
}
