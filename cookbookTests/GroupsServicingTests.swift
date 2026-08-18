//
//  GroupsServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct GroupsServicingTests {

    private func makeGroupDetails(
        name: String = "Barrentine Family",
        locationText: String = "Memphis, TN",
        visibility: GroupVisibility = .publicGroup,
        approvalPolicy: JoinApprovalPolicy = .anyAdministrator
    ) -> NewGroupDetails {
        NewGroupDetails(
            name: name,
            description: "A family cookbook",
            type: "Family",
            locationText: locationText,
            structuredRegion: nil,
            visibility: visibility,
            allowsMemberInvites: false,
            approvalPolicy: approvalPolicy
        )
    }

    private func makeCookbookDetails(
        cookbookName: String = "Barrentine Family Reunion",
        allowsMemberPublishing: Bool = true
    ) -> NewGroupCookbookDetails {
        NewGroupCookbookDetails(cookbookName: cookbookName, allowsMemberPublishing: allowsMemberPublishing)
    }

    @discardableResult
    private func createTestGroup(
        _ service: InMemoryGroupsService,
        groupDetails: NewGroupDetails? = nil,
        cookbookDetails: NewGroupCookbookDetails? = nil,
        creatorUserID: String = "alice",
        creatorDisplayName: String = "Alice",
        idempotencyKey: String = "req-1"
    ) async throws -> (FamilyGroup, GroupCookbook) {
        try await service.createGroup(
            groupDetails ?? makeGroupDetails(),
            cookbookDetails: cookbookDetails ?? makeCookbookDetails(),
            creatorUserID: creatorUserID,
            creatorDisplayName: creatorDisplayName,
            idempotencyKey: idempotencyKey
        )
    }

    @Test func createGroupConsumesOneCreditAndMakesCreatorFounderAdmin() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 2

        let (group, cookbook) = try await createTestGroup(service)

        #expect(service.tier2CreditsByUserID["alice"] == 1)
        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.count == 1)
        #expect(memberships.first?.role == .admin)
        #expect(memberships.first?.userID == "alice")
        #expect(cookbook.groupID == group.id)
        #expect(cookbook.createdByUserID == "alice")
    }

    @Test func createGroupWithNoCreditsThrows() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 0

        await #expect(throws: GroupsServiceError.insufficientCredits) {
            try await createTestGroup(service)
        }
    }

    @Test func createGroupWithExpiredCreditThrowsCreditExpired() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        service.tier2ExpiresAtByUserID["alice"] = Date(timeIntervalSince1970: 0)

        await #expect(throws: GroupsServiceError.creditExpired) {
            try await createTestGroup(service)
        }
        // Untouched — the credit is still there, just unusable.
        #expect(service.tier2CreditsByUserID["alice"] == 1)
    }

    @Test func createGroupSucceedsWhenExpirationIsStillInTheFuture() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        service.tier2ExpiresAtByUserID["alice"] = LaunchCreditPromo.tier2ExpirationDate

        let (group, _) = try await createTestGroup(service)

        #expect(service.tier2CreditsByUserID["alice"] == 0)
        #expect(group.createdByUserID == "alice")
    }

    @Test func repeatedCreateGroupCallWithSameIdempotencyKeyDoesNotDoubleCharge() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1

        let (first, firstCookbook) = try await createTestGroup(service)
        let (second, secondCookbook) = try await createTestGroup(service)

        #expect(first.id == second.id)
        #expect(firstCookbook.id == secondCookbook.id)
        #expect(service.tier2CreditsByUserID["alice"] == 0)
        #expect(service.groups.count == 1)
        #expect(service.groupCookbooks.count == 1)
    }

    @Test func adminCanApproveJoinRequest() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)

        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: "Cousin Bob")
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "bob" && $0.role == .member && $0.status == .active })
    }

    @Test func requestToJoinGrantsMembershipImmediatelyWhenTheGroupNeedsNoApproval() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service, groupDetails: makeGroupDetails(approvalPolicy: .noApprovalNeeded))

        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)

        #expect(request.state == .approved)
        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "bob" && $0.role == .member && $0.status == .active && $0.source == .auto })
        // No pending join request is left behind for anyone to review.
        let pending = try await service.fetchJoinRequests(forGroup: group.id)
        #expect(pending.isEmpty)
    }

    @Test func requestToJoinStillRequiresApprovalWhenTheGroupRequiresIt() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)

        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)

        #expect(request.state == .pending)
        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(!memberships.contains { $0.userID == "bob" })
    }

    @Test func nonAdminCannotDecideJoinRequestUnderTheDefaultAnyAdministratorPolicy() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)

        await #expect(throws: GroupsServiceError.notAuthorized) {
            try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "bob")
        }
    }

    @Test func underACreatorOnlyPolicyTheCreatorCanDecideEvenWithoutAnAdminMembership() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service, groupDetails: makeGroupDetails(approvalPolicy: .creatorOnly))
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "carol", note: nil)

        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "carol" && $0.status == .active })
    }

    @Test func underACreatorOnlyPolicyAnAdminWhoIsNotTheCreatorCannotDecide() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service, groupDetails: makeGroupDetails(approvalPolicy: .creatorOnly))
        let bobJoin = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(bobJoin.id, approve: true, decidedByUserID: "alice")
        try await service.updateRole(groupID: group.id, userID: "bob", newRole: .admin, actingUserID: "alice")
        let carolRequest = try await service.requestToJoin(groupID: group.id, requesterID: "carol", note: nil)

        await #expect(throws: GroupsServiceError.notAuthorized) {
            try await service.decideJoinRequest(carolRequest.id, approve: true, decidedByUserID: "bob")
        }
    }

    @Test func underAnAnyUserPolicyAPlainMemberCanDecide() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service, groupDetails: makeGroupDetails(approvalPolicy: .anyUser))
        let bobJoin = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(bobJoin.id, approve: true, decidedByUserID: "alice")
        let carolRequest = try await service.requestToJoin(groupID: group.id, requesterID: "carol", note: nil)

        try await service.decideJoinRequest(carolRequest.id, approve: true, decidedByUserID: "bob")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "carol" && $0.status == .active })
    }

    @Test func acceptingInvitationCreatesMembershipWithOfferedRole() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)

        let invitation = try await service.invite(groupID: group.id, inviterID: "alice", inviteeIdentifier: "carol@example.com", role: .member)
        try await service.respondToInvitation(invitation.id, accept: true, respondingUserID: "carol")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "carol" && $0.source == .invite })
    }

    /// Distinct from a solo admin leaving an otherwise-empty group (see
    /// `lastActiveMemberLeavingDeletesTheWholeGroup`) — this is the case
    /// where leaving would strand a still-populated group with no admin,
    /// which stays blocked.
    @Test func lastAdminCannotLeaveGroupWhileOtherActiveMembersRemain() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")

        await #expect(throws: GroupsServiceError.lastAdminCannotLeaveOrBeDemoted) {
            try await service.leaveGroup(groupID: group.id, userID: "alice")
        }
    }

    @Test func lastActiveMemberLeavingDeletesTheWholeGroup() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)

        try await service.leaveGroup(groupID: group.id, userID: "alice")

        let remaining = try await service.fetchGroup(id: group.id)
        #expect(remaining == nil)
        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.isEmpty)
        let remainingCookbooks = try await service.fetchGroupCookbooks(forGroup: group.id)
        #expect(remainingCookbooks.isEmpty)
    }

    /// The "last active member" rule doesn't care whether that member is
    /// an admin or not — role only matters for the "populated but
    /// adminless" protection above.
    @Test func lastActiveMemberOfAnyRoleLeavingDeletesTheGroup() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")
        try await service.updateRole(groupID: group.id, userID: "bob", newRole: .admin, actingUserID: "alice")
        try await service.leaveGroup(groupID: group.id, userID: "alice")

        try await service.leaveGroup(groupID: group.id, userID: "bob")

        let remaining = try await service.fetchGroup(id: group.id)
        #expect(remaining == nil)
    }

    @Test func lastAdminCannotBeDemoted() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)

        await #expect(throws: GroupsServiceError.lastAdminCannotLeaveOrBeDemoted) {
            try await service.updateRole(groupID: group.id, userID: "alice", newRole: .member, actingUserID: "alice")
        }
    }

    @Test func secondAdminCanLeaveOncePromoted() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")
        try await service.updateRole(groupID: group.id, userID: "bob", newRole: .admin, actingUserID: "alice")

        try await service.leaveGroup(groupID: group.id, userID: "alice")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.first { $0.userID == "alice" }?.status == .left)
    }

    @Test func adminCanAddAFurtherCookbookToAnExistingGroup() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, firstCookbook) = try await createTestGroup(service)

        let second = try await service.createGroupCookbook(
            makeCookbookDetails(cookbookName: "Barrentine Summer Cookout"),
            in: group.id,
            creatorUserID: "alice",
            creatorDisplayName: "Alice"
        )

        let cookbooks = try await service.fetchGroupCookbooks(forGroup: group.id)
        #expect(cookbooks.count == 2)
        #expect(cookbooks.contains { $0.id == firstCookbook.id })
        #expect(second.cookbookName == "Barrentine Summer Cookout")
    }

    @Test func nonAdminCannotAddAFurtherCookbook() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")

        await #expect(throws: GroupsServiceError.notAuthorized) {
            try await service.createGroupCookbook(makeCookbookDetails(), in: group.id, creatorUserID: "bob", creatorDisplayName: "Bob")
        }
    }

    @Test func fetchPublicGroupCookbooksOnlyReturnsCookbooksFromPublicActiveGroups() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 2
        let (_, publicCookbook) = try await createTestGroup(
            service,
            groupDetails: makeGroupDetails(visibility: .publicGroup),
            cookbookDetails: makeCookbookDetails(cookbookName: "Findable Feast"),
            idempotencyKey: "req-1"
        )
        _ = try await createTestGroup(
            service,
            groupDetails: makeGroupDetails(visibility: .privateGroup),
            cookbookDetails: makeCookbookDetails(cookbookName: "Hidden Feast"),
            idempotencyKey: "req-2"
        )

        let results = try await service.fetchPublicGroupCookbooks(matching: PublicGroupCookbookSearchFilter(text: "Feast"))

        #expect(results.map(\.id) == [publicCookbook.id])
    }

    @Test func fetchJoinRequestsForGroupOnlyReturnsPending() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let bobRequest = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        _ = try await service.requestToJoin(groupID: group.id, requesterID: "carol", note: nil)
        try await service.decideJoinRequest(bobRequest.id, approve: true, decidedByUserID: "alice")

        let pending = try await service.fetchJoinRequests(forGroup: group.id)

        #expect(pending.count == 1)
        #expect(pending.first?.requesterID == "carol")
    }

    @Test func fetchJoinRequestsByRequesterIncludesDecidedOnes() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: false, decidedByUserID: "alice")

        let bobsRequests = try await service.fetchJoinRequests(byRequester: "bob")

        #expect(bobsRequests.count == 1)
        #expect(bobsRequests.first?.state == .denied)
    }

    @Test func fetchInvitationsForInviteeOnlyReturnsPendingOnesForThatEmail() async throws {
        let service = InMemoryGroupsService()
        service.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await createTestGroup(service)
        let carolInvite = try await service.invite(groupID: group.id, inviterID: "alice", inviteeIdentifier: "carol@example.com", role: .member)
        _ = try await service.invite(groupID: group.id, inviterID: "alice", inviteeIdentifier: "dave@example.com", role: .member)
        try await service.respondToInvitation(carolInvite.id, accept: true, respondingUserID: "carol")

        let pendingForDave = try await service.fetchInvitations(forInvitee: "dave@example.com")
        let pendingForCarol = try await service.fetchInvitations(forInvitee: "carol@example.com")

        #expect(pendingForDave.count == 1)
        #expect(pendingForCarol.isEmpty)
    }
}
