//
//  GroupsServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct GroupsServicingTests {

    private func makeDetails(
        name: String = "Barrentine Family",
        cookbookName: String = "Barrentine Family Reunion",
        locationText: String = "Memphis, TN",
        visibility: GroupVisibility = .publicGroup
    ) -> NewGroupDetails {
        NewGroupDetails(
            name: name,
            cookbookName: cookbookName,
            description: "A family cookbook",
            type: "Family",
            locationText: locationText,
            structuredRegion: nil,
            visibility: visibility,
            allowsMemberInvites: false,
            allowsMemberPublishing: true
        )
    }

    @Test func createGroupConsumesOneCreditAndMakesCreatorFounderAdmin() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 2

        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        #expect(service.creditsByUserID["alice"] == 1)
        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.count == 1)
        #expect(memberships.first?.role == .admin)
        #expect(memberships.first?.userID == "alice")
    }

    @Test func createGroupWithNoCreditsThrows() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 0

        await #expect(throws: GroupsServiceError.insufficientCredits) {
            try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        }
    }

    @Test func repeatedCreateGroupCallWithSameIdempotencyKeyDoesNotDoubleCharge() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1

        let first = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        let second = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        #expect(first.id == second.id)
        #expect(service.creditsByUserID["alice"] == 0)
        #expect(service.groups.count == 1)
    }

    @Test func adminCanApproveJoinRequest() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: "Cousin Bob")
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "bob" && $0.role == .member && $0.status == .active })
    }

    @Test func nonAdminCannotDecideJoinRequest() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)

        await #expect(throws: GroupsServiceError.notAuthorized) {
            try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "bob")
        }
    }

    @Test func acceptingInvitationCreatesMembershipWithOfferedRole() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        let invitation = try await service.invite(groupID: group.id, inviterID: "alice", inviteeIdentifier: "carol@example.com", role: .member)
        try await service.respondToInvitation(invitation.id, accept: true, respondingUserID: "carol")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.contains { $0.userID == "carol" && $0.source == .invite })
    }

    @Test func lastAdminCannotLeaveGroup() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        await #expect(throws: GroupsServiceError.lastAdminCannotLeaveOrBeDemoted) {
            try await service.leaveGroup(groupID: group.id, userID: "alice")
        }
    }

    @Test func lastAdminCannotBeDemoted() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        await #expect(throws: GroupsServiceError.lastAdminCannotLeaveOrBeDemoted) {
            try await service.updateRole(groupID: group.id, userID: "alice", newRole: .member, actingUserID: "alice")
        }
    }

    @Test func secondAdminCanLeaveOncePromoted() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: true, decidedByUserID: "alice")
        try await service.updateRole(groupID: group.id, userID: "bob", newRole: .admin, actingUserID: "alice")

        try await service.leaveGroup(groupID: group.id, userID: "alice")

        let memberships = try await service.fetchMemberships(forGroup: group.id)
        #expect(memberships.first { $0.userID == "alice" }?.status == .left)
    }

    @Test func createGroupRejectsADuplicateCookbookNameFamilyNameLocationCombination() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 2
        _ = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        await #expect(throws: GroupsServiceError.duplicateCookbookIdentity) {
            try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-2")
        }
    }

    @Test func createGroupAllowsDistinctCombinationsEvenWithASharedField() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 3
        _ = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")

        // Same family name and location, different cookbook name — a
        // distinct combination, so this should succeed.
        let second = try await service.createGroup(
            makeDetails(cookbookName: "Barrentine Summer Cookout"),
            creatorUserID: "alice",
            idempotencyKey: "req-2"
        )

        #expect(service.groups.count == 2)
        #expect(second.cookbookName == "Barrentine Summer Cookout")
    }

    @Test func fetchJoinRequestsForGroupOnlyReturnsPending() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        let bobRequest = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        _ = try await service.requestToJoin(groupID: group.id, requesterID: "carol", note: nil)
        try await service.decideJoinRequest(bobRequest.id, approve: true, decidedByUserID: "alice")

        let pending = try await service.fetchJoinRequests(forGroup: group.id)

        #expect(pending.count == 1)
        #expect(pending.first?.requesterID == "carol")
    }

    @Test func fetchJoinRequestsByRequesterIncludesDecidedOnes() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        let request = try await service.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await service.decideJoinRequest(request.id, approve: false, decidedByUserID: "alice")

        let bobsRequests = try await service.fetchJoinRequests(byRequester: "bob")

        #expect(bobsRequests.count == 1)
        #expect(bobsRequests.first?.state == .denied)
    }

    @Test func fetchInvitationsForInviteeOnlyReturnsPendingOnesForThatEmail() async throws {
        let service = InMemoryGroupsService()
        service.creditsByUserID["alice"] = 1
        let group = try await service.createGroup(makeDetails(), creatorUserID: "alice", idempotencyKey: "req-1")
        let carolInvite = try await service.invite(groupID: group.id, inviterID: "alice", inviteeIdentifier: "carol@example.com", role: .member)
        _ = try await service.invite(groupID: group.id, inviterID: "alice", inviteeIdentifier: "dave@example.com", role: .member)
        try await service.respondToInvitation(carolInvite.id, accept: true, respondingUserID: "carol")

        let pendingForDave = try await service.fetchInvitations(forInvitee: "dave@example.com")
        let pendingForCarol = try await service.fetchInvitations(forInvitee: "carol@example.com")

        #expect(pendingForDave.count == 1)
        #expect(pendingForCarol.isEmpty)
    }
}
