//
//  InMemoryGroupsService.swift
//  cookbook
//

import Foundation

final class InMemoryGroupsService: GroupsServicing {
    private(set) var groups: [FamilyGroup] = []
    private(set) var memberships: [Membership] = []
    private(set) var joinRequests: [JoinRequest] = []
    private(set) var invitations: [Invitation] = []

    /// Mirrors the `entitlements/{uid}.creationCredits` counter the real
    /// adapter reads/writes via Firestore.
    var creditsByUserID: [String: Int] = [:]
    private var processedIdempotencyKeys: [String: String] = [:] // key -> created group id

    func createGroup(_ details: NewGroupDetails, creatorUserID: String, idempotencyKey: String) async throws -> FamilyGroup {
        if let existingGroupID = processedIdempotencyKeys[idempotencyKey],
           let existingGroup = groups.first(where: { $0.id == existingGroupID }) {
            return existingGroup
        }

        let availableCredits = creditsByUserID[creatorUserID] ?? 0
        guard availableCredits > 0 else {
            throw GroupsServiceError.insufficientCredits
        }

        let group = FamilyGroup(
            id: UUID().uuidString,
            slug: UUID().uuidString.lowercased(),
            name: details.name,
            description: details.description,
            type: details.type,
            locationText: details.locationText,
            structuredRegion: details.structuredRegion,
            coverImageURL: nil,
            visibility: details.visibility,
            createdByUserID: creatorUserID,
            createdAt: .now,
            status: .active,
            allowsMemberInvites: details.allowsMemberInvites,
            allowsMemberPublishing: details.allowsMemberPublishing
        )
        let founderMembership = Membership(
            id: Membership.compositeID(groupID: group.id, userID: creatorUserID),
            groupID: group.id,
            userID: creatorUserID,
            role: .admin,
            status: .active,
            source: .founder,
            joinedAt: .now,
            leftAt: nil
        )

        creditsByUserID[creatorUserID] = availableCredits - 1
        groups.append(group)
        upsertMembership(founderMembership)
        processedIdempotencyKeys[idempotencyKey] = group.id

        return group
    }

    func fetchPublicGroups(matching query: String?) async throws -> [FamilyGroup] {
        let publicGroups = groups.filter { $0.visibility == .publicGroup && $0.status == .active }
        guard let query, !query.isEmpty else { return publicGroups }
        return publicGroups.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    func fetchGroup(id: String) async throws -> FamilyGroup? {
        groups.first { $0.id == id }
    }

    func fetchMemberships(forGroup groupID: String) async throws -> [Membership] {
        memberships.filter { $0.groupID == groupID }
    }

    func fetchMemberships(forUser userID: String) async throws -> [Membership] {
        memberships.filter { $0.userID == userID }
    }

    func requestToJoin(groupID: String, requesterID: String, note: String?) async throws -> JoinRequest {
        guard groups.contains(where: { $0.id == groupID }) else {
            throw GroupsServiceError.groupNotFound
        }
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard !GroupPolicy.isActiveMember(requesterID, in: groupMemberships) else {
            throw GroupsServiceError.alreadyMember
        }

        let request = JoinRequest(
            id: UUID().uuidString,
            groupID: groupID,
            requesterID: requesterID,
            note: note,
            state: .pending,
            decidedByUserID: nil,
            createdAt: .now,
            decidedAt: nil
        )
        joinRequests.append(request)
        return request
    }

    func decideJoinRequest(_ requestID: String, approve: Bool, decidedByUserID: String) async throws {
        guard let index = joinRequests.firstIndex(where: { $0.id == requestID }) else {
            throw GroupsServiceError.joinRequestNotFound
        }
        var request = joinRequests[index]
        guard request.state == .pending else {
            throw GroupsServiceError.invalidState
        }

        let groupMemberships = try await fetchMemberships(forGroup: request.groupID)
        guard GroupPolicy.isActiveAdmin(decidedByUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }

        request.state = approve ? .approved : .denied
        request.decidedByUserID = decidedByUserID
        request.decidedAt = .now
        joinRequests[index] = request

        if approve {
            upsertMembership(Membership(
                id: Membership.compositeID(groupID: request.groupID, userID: request.requesterID),
                groupID: request.groupID,
                userID: request.requesterID,
                role: .member,
                status: .active,
                source: .request,
                joinedAt: .now,
                leftAt: nil
            ))
        }
    }

    func invite(groupID: String, inviterID: String, inviteeIdentifier: String, role: MembershipRole) async throws -> Invitation {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard let group = try await fetchGroup(id: groupID) else {
            throw GroupsServiceError.groupNotFound
        }
        let canInvite = GroupPolicy.isActiveAdmin(inviterID, in: groupMemberships)
            || (group.allowsMemberInvites && GroupPolicy.isActiveMember(inviterID, in: groupMemberships))
        guard canInvite else {
            throw GroupsServiceError.notAuthorized
        }

        let invitation = Invitation(
            id: UUID().uuidString,
            groupID: groupID,
            inviterID: inviterID,
            inviteeIdentifier: inviteeIdentifier,
            role: role,
            tokenHash: NonceGenerator.sha256(UUID().uuidString),
            expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            state: .pending
        )
        invitations.append(invitation)
        return invitation
    }

    func respondToInvitation(_ invitationID: String, accept: Bool, respondingUserID: String) async throws {
        guard let index = invitations.firstIndex(where: { $0.id == invitationID }) else {
            throw GroupsServiceError.invitationNotFound
        }
        var invitation = invitations[index]
        guard invitation.state == .pending, invitation.expiresAt > .now else {
            throw GroupsServiceError.invalidState
        }

        invitation.state = accept ? .accepted : .declined
        invitations[index] = invitation

        if accept {
            upsertMembership(Membership(
                id: Membership.compositeID(groupID: invitation.groupID, userID: respondingUserID),
                groupID: invitation.groupID,
                userID: respondingUserID,
                role: invitation.role,
                status: .active,
                source: .invite,
                joinedAt: .now,
                leftAt: nil
            ))
        }
    }

    private func upsertMembership(_ membership: Membership) {
        if let index = memberships.firstIndex(where: { $0.id == membership.id }) {
            memberships[index] = membership
        } else {
            memberships.append(membership)
        }
    }

    func updateRole(groupID: String, userID: String, newRole: MembershipRole, actingUserID: String) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        guard let index = memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        if newRole == .member, GroupPolicy.isLastActiveAdmin(userID, in: groupMemberships) {
            throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
        }
        memberships[index].role = newRole
    }

    func leaveGroup(groupID: String, userID: String) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        if GroupPolicy.isLastActiveAdmin(userID, in: groupMemberships) {
            throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
        }
        guard let index = memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        memberships[index].status = .left
        memberships[index].leftAt = .now
    }

    func archiveGroup(groupID: String, actingUserID: String) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        guard let index = groups.firstIndex(where: { $0.id == groupID }) else {
            throw GroupsServiceError.groupNotFound
        }
        groups[index].status = .archived
    }
}
