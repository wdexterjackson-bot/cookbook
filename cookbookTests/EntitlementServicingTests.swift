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
