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
    private var claimedUniquenessKeys: Set<String> = []

    func createGroup(_ details: NewGroupDetails, creatorUserID: String, idempotencyKey: String) async throws -> FamilyGroup {
        if let existingGroupID = processedIdempotencyKeys[idempotencyKey],
           let existingGroup = groups.first(where: { $0.id == existingGroupID }) {
            return existingGroup
        }

        let availableCredits = creditsByUserID[creatorUserID] ?? 0
        guard availableCredits > 0 else {
            throw GroupsServiceError.insufficientCredits
        }

        let uniquenessKey = FamilyGroup.uniquenessKey(cookbookName: details.cookbookName, familyName: details.name, locationText: details.locationText)
        guard !claimedUniquenessKeys.contains(uniquenessKey) else {
            throw GroupsServiceError.duplicateCookbookIdentity
        }

        let group = FamilyGroup(
            id: UUID().uuidString,
            slug: UUID().uuidString.lowercased(),
            name: details.name,
            cookbookName: details.cookbookName,
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
            allowsMemberPublishing: details.allowsMemberPublishing,
            autoApproveJoinRequests: details.autoApproveJoinRequests
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
        claimedUniquenessKeys.insert(uniquenessKey)

        return group
    }

    func fetchPublicGroups(matching filter: PublicGroupSearchFilter) async throws -> [FamilyGroup] {
        var publicGroups = groups.filter { $0.visibility == .publicGroup && $0.status == .active }
        if let text = filter.text, !text.isEmpty {
            publicGroups = publicGroups.filter {
                $0.cookbookName.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)
            }
        }
        if let locationText = filter.locationText, !locationText.isEmpty {
            publicGroups = publicGroups.filter { $0.locationText.localizedCaseInsensitiveContains(locationText) }
        }
        return publicGroups
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
        guard let group = groups.first(where: { $0.id == groupID }) else {
            throw GroupsServiceError.groupNotFound
        }
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard !GroupPolicy.isActiveMember(requesterID, in: groupMemberships) else {
            throw GroupsServiceError.alreadyMember
        }

        if group.autoApproveJoinRequests {
            let membership = Membership(
                id: Membership.compositeID(groupID: groupID, userID: requesterID),
                groupID: groupID,
                userID: requesterID,
                role: .member,
                status: .active,
                source: .auto,
                joinedAt: .now,
                leftAt: nil
            )
            upsertMembership(membership)
            return JoinRequest(
                id: membership.id,
                groupID: groupID,
                requesterID: requesterID,
                note: note,
                state: .approved,
                decidedByUserID: requesterID,
                createdAt: .now,
                decidedAt: .now
            )
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

    func fetchJoinRequests(forGroup groupID: String) async throws -> [JoinRequest] {
        joinRequests.filter { $0.groupID == groupID && $0.state == .pending }
    }

    func fetchJoinRequests(byRequester userID: String) async throws -> [JoinRequest] {
        joinRequests.filter { $0.requesterID == userID }
    }

    func fetchInvitations(forInvitee identifier: String) async throws -> [Invitation] {
        invitations.filter { $0.inviteeIdentifier == identifier && $0.state == .pending }
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
        if GroupPolicy.isLastActiveMember(userID, in: groupMemberships) {
            try await deleteGroupPermanently(groupID: groupID)
            return
        }
        if GroupPolicy.isLastActiveAdmin(userID, in: groupMemberships) {
            throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
        }
        guard let index = memberships.firstIndex(where: { $0.groupID == groupID && $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        memberships[index].status = .left
        memberships[index].leftAt = .now
    }

    func deleteGroupPermanently(groupID: String) async throws {
        groups.removeAll { $0.id == groupID }
        memberships.removeAll { $0.groupID == groupID }
        joinRequests.removeAll { $0.groupID == groupID }
        invitations.removeAll { $0.groupID == groupID }
    }
}
