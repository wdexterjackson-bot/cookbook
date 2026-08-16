//
//  EntitlementServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct EntitlementServicingTests {

    @Test func availableCreditsReflectStoredEntitlement() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice",
            tier1Credits: 1,
            tier2Credits: 3,
            isProUser: true,
            receivedTier1PromoCredit: true,
            receivedTier2PromoCredits: true,
            createdAt: .now
        )

        #expect(try await service.availableTier2Credits(userID: "alice") == 3)
        #expect(try await service.availableTier1Credits(userID: "alice") == 1)
        #expect(try await service.isProUser(userID: "alice") == true)
    }

    @Test func missingEntitlementDefaultsToZeroCreditsAndNotPro() async throws {
        let service = InMemoryEntitlementService()

        #expect(try await service.availableTier2Credits(userID: "nobody") == 0)
        #expect(try await service.availableTier1Credits(userID: "nobody") == 0)
        #expect(try await service.isProUser(userID: "nobody") == false)
    }

    @Test func redeemTier1CreditFlipsBothFieldsWhenAvailable() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 1, tier2Credits: 3, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        let redeemed = try await service.redeemTier1CreditForProUser(userID: "alice")

        #expect(redeemed)
        #expect(try await service.isProUser(userID: "alice") == true)
        #expect(service.entitlementsByUserID["alice"]?.tier1Credits == 0)
        #expect(service.entitlementsByUserID["alice"]?.tier2Credits == 3)
    }

    @Test func redeemTier1CreditFailsWhenNoCreditOrMissing() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 3, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        #expect(try await service.redeemTier1CreditForProUser(userID: "alice") == false)
        #expect(try await service.redeemTier1CreditForProUser(userID: "nobody") == false)
    }

    @Test func redeemTier1CreditFailsWhenAlreadyPro() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 1, tier2Credits: 3, isProUser: true,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        #expect(try await service.redeemTier1CreditForProUser(userID: "alice") == false)
    }

    @Test func redeemTier1CreditThrowsCreditExpiredWhenPastItsExpirationDate() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 1, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
            tier1ExpiresAt: Date(timeIntervalSince1970: 0)
        )

        await #expect(throws: EntitlementServiceError.creditExpired) {
            try await service.redeemTier1CreditForProUser(userID: "alice")
        }
        // Untouched — the credit is still there, just unusable.
        #expect(service.entitlementsByUserID["alice"]?.tier1Credits == 1)
        #expect(service.entitlementsByUserID["alice"]?.isProUser == false)
    }

    @Test func redeemTier1CreditSucceedsWhenExpirationIsStillInTheFuture() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 1, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
            tier1ExpiresAt: LaunchCreditPromo.tier1ExpirationDate
        )

        #expect(try await service.redeemTier1CreditForProUser(userID: "alice"))
    }

    // MARK: - Discount codes / Annual Pro Membership credit

    @Test func applyDiscountCodeGrantsOneAnnualCreditAndRecordsTheCode() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        try await service.applyDiscountCode("7595SLEDGERD", userID: "alice")

        #expect(service.entitlementsByUserID["alice"]?.annualProMembershipCredits == 1)
        #expect(service.entitlementsByUserID["alice"]?.redeemedDiscountCodes == ["7595SLEDGERD"])
    }

    @Test func applyDiscountCodeIsCaseInsensitiveAndTrimsWhitespace() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        try await service.applyDiscountCode("  7595sledgerd  ", userID: "alice")

        #expect(service.entitlementsByUserID["alice"]?.annualProMembershipCredits == 1)
    }

    @Test func applyDiscountCodeThrowsInvalidForAnUnknownCode() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        await #expect(throws: EntitlementServiceError.invalidDiscountCode) {
            try await service.applyDiscountCode("NOT-A-REAL-CODE", userID: "alice")
        }
        #expect(service.entitlementsByUserID["alice"]?.annualProMembershipCredits == 0)
    }

    @Test func applyDiscountCodeThrowsAlreadyRedeemedOnSecondAttempt() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
            redeemedDiscountCodes: ["7595SLEDGERD"]
        )

        await #expect(throws: EntitlementServiceError.discountCodeAlreadyRedeemed) {
            try await service.applyDiscountCode("7595SLEDGERD", userID: "alice")
        }
        // Untouched — still exactly one credit's worth of history, not a
        // second grant sneaking through under a thrown error.
        #expect(service.entitlementsByUserID["alice"]?.annualProMembershipCredits == 0)
    }

    @Test func redeemAnnualProMembershipCreditActivatesRoughlyOneYearOut() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now,
            annualProMembershipCredits: 1
        )

        let redeemed = try await service.redeemAnnualProMembershipCredit(userID: "alice")

        #expect(redeemed)
        #expect(service.entitlementsByUserID["alice"]?.annualProMembershipCredits == 0)
        let expiresAt = try #require(service.entitlementsByUserID["alice"]?.annualProMembershipExpiresAt)
        let daysOut = expiresAt.timeIntervalSinceNow / 86400
        #expect(daysOut > 364 && daysOut < 366)
    }

    @Test func redeemAnnualProMembershipCreditFailsWhenNoneAvailable() async throws {
        let service = InMemoryEntitlementService()
        service.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        #expect(try await service.redeemAnnualProMembershipCredit(userID: "alice") == false)
    }

    // MARK: - EntitlementGate decision logic

    @Test func groupCreationGateNeedsConfirmationWhenCreditsAvailable() {
        let entitlement = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 2, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )
        #expect(EntitlementGate.forGroupCreation(entitlement) == .needsConfirmation(creditsAvailable: 2))
    }

    @Test func groupCreationGateNeedsPurchaseWhenNoCreditsOrNoEntitlement() {
        let entitlement = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )
        #expect(EntitlementGate.forGroupCreation(entitlement) == .needsPurchase)
        #expect(EntitlementGate.forGroupCreation(nil) == .needsPurchase)
    }

    @Test func groupJoinGateExemptForMFBRegardlessOfEntitlement() {
        let mfbGroup = FamilyGroup.previewStub(isMFB: true)
        #expect(EntitlementGate.forGroupJoin(nil, group: mfbGroup) == .exempt)
    }

    @Test func groupJoinGateExemptWhenAlreadyPro() {
        let group = FamilyGroup.previewStub(isMFB: false)
        let entitlement = Entitlement(
            userID: "alice", tier1Credits: 0, tier2Credits: 0, isProUser: true,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )
        #expect(EntitlementGate.forGroupJoin(entitlement, group: group) == .exempt)
    }

    @Test func groupJoinGateNeedsConfirmationWhenTier1CreditAvailable() {
        let group = FamilyGroup.previewStub(isMFB: false)
        let entitlement = Entitlement(
            userID: "alice", tier1Credits: 1, tier2Credits: 0, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )
        #expect(EntitlementGate.forGroupJoin(entitlement, group: group) == .needsConfirmation(creditsAvailable: 1))
    }

    @Test func groupJoinGateNeedsPurchaseWhenNotProAndNoCredit() {
        let group = FamilyGroup.previewStub(isMFB: false)
        #expect(EntitlementGate.forGroupJoin(nil, group: group) == .needsPurchase)
    }
}

private extension FamilyGroup {
    static func previewStub(isMFB: Bool) -> FamilyGroup {
        FamilyGroup(
            id: "group-1",
            slug: "group-1",
            name: "Jackson",
            cookbookName: "Jackson Family Reunion",
            description: "",
            type: "Family",
            locationText: "Baltimore, MD",
            structuredRegion: nil,
            coverImageURL: nil,
            visibility: .publicGroup,
            createdByUserID: "creator",
            createdAt: .now,
            status: .active,
            allowsMemberInvites: false,
            allowsMemberPublishing: true,
            autoApproveJoinRequests: false,
            isMFB: isMFB
        )
    }
}
