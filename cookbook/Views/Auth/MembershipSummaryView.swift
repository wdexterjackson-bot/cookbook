//
//  MembershipSummaryView.swift
//  cookbook
//
//  Shared between AccountView's Settings and MembershipPaywallView's own
//  "Your Membership" section — both showed the same three rows
//  independently before this, which is exactly the kind of duplication
//  that drifts. "Pro User: Yes/No" reads as a rejection rather than a
//  status, so it's replaced with a plain membership-level label; credit
//  rows are omitted entirely at zero rather than showing "0", since an
//  absent row reads cleaner than a count nobody can do anything with.
//

import SwiftUI

struct MembershipSummaryView: View {
    let entitlement: Entitlement?

    private var isProUser: Bool { entitlement?.isProUser ?? false }

    /// Three levels: Standard, Pro User, Annual Pro Membership. An active
    /// Annual Pro Membership takes precedence over the plain lifetime Pro
    /// User flag when both happen to be true — it's the more specific,
    /// currently-active status of the two, and the one worth surfacing
    /// while it hasn't expired.
    private var membershipLevelLabel: String {
        if entitlement?.isActiveAnnualProMember == true {
            return "Annual Pro Membership"
        } else if isProUser {
            return "Pro User"
        } else {
            return "Standard User"
        }
    }

    var body: some View {
        LabeledContent("Membership Level", value: membershipLevelLabel)
        if let tier1Credits = entitlement?.tier1Credits, tier1Credits > 0 {
            LabeledContent("Pro User Credits") {
                creditValueText(count: tier1Credits, expiresAt: entitlement?.tier1ExpiresAt)
            }
        }
        if let tier2Credits = entitlement?.tier2Credits, tier2Credits > 0 {
            LabeledContent("Community Cookbook Credits") {
                creditValueText(count: tier2Credits, expiresAt: entitlement?.tier2ExpiresAt)
            }
        }
        if entitlement?.isActiveAnnualProMember == true, let expiresAt = entitlement?.annualProMembershipExpiresAt {
            LabeledContent("Annual Pro Membership") {
                Text("Active until \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
            }
        }
        if !isProUser, let tier1Credits = entitlement?.tier1Credits, tier1Credits > 0,
           let tier1ExpiresAt = entitlement?.tier1ExpiresAt, tier1ExpiresAt > .now {
            Text("Upgrading to Pro User is free until \(tier1ExpiresAt.formatted(date: .abbreviated, time: .omitted)) using your existing credit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func creditValueText(count: Int, expiresAt: Date?) -> some View {
        if let expiresAt {
            if expiresAt > .now {
                Text("\(count) (expires \(expiresAt.formatted(date: .abbreviated, time: .omitted)))")
            } else {
                Text("\(count) (expired)")
            }
        } else {
            Text("\(count)")
        }
    }
}

#Preview {
    Form {
        Section("Standard, no credits") {
            MembershipSummaryView(entitlement: Entitlement(
                userID: "preview", tier1Credits: 0, tier2Credits: 0, isProUser: false,
                receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
            ))
        }
        Section("Standard, has unexpired credits") {
            MembershipSummaryView(entitlement: Entitlement(
                userID: "preview", tier1Credits: 1, tier2Credits: 2, isProUser: false,
                receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
                tier1ExpiresAt: LaunchCreditPromo.tier1ExpirationDate, tier2ExpiresAt: LaunchCreditPromo.tier2ExpirationDate
            ))
        }
        Section("Standard, expired tier1 credit") {
            MembershipSummaryView(entitlement: Entitlement(
                userID: "preview", tier1Credits: 1, tier2Credits: 0, isProUser: false,
                receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
                tier1ExpiresAt: Date(timeIntervalSince1970: 0)
            ))
        }
        Section("Pro User") {
            MembershipSummaryView(entitlement: Entitlement(
                userID: "preview", tier1Credits: 0, tier2Credits: 1, isProUser: true,
                receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
                tier2ExpiresAt: LaunchCreditPromo.tier2ExpirationDate
            ))
        }
        Section("Active Annual Pro Membership, not otherwise Pro") {
            MembershipSummaryView(entitlement: Entitlement(
                userID: "preview", tier1Credits: 0, tier2Credits: 0, isProUser: false,
                receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
                annualProMembershipExpiresAt: .now.addingTimeInterval(60 * 60 * 24 * 200)
            ))
        }
    }
}
