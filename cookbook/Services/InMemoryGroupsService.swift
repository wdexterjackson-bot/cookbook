//
//  InMemoryGroupsService.swift
//  cookbook
//

import Foundation

final class InMemoryGroupsService: GroupsServicing {
    private(set) var groups: [FamilyGroup] = []
    private(set) var groupCookbooks: [GroupCookbook] = []
    private(set) var memberships: [Membership] = []
    private(set) var joinRequests: [JoinRequest] = []
    private(set) var invitations: [Invitation] = []

    /// Mirrors the `entitlements/{uid}.tier2Credits` counter the real
    /// adapter reads/writes via Firestore.
    var tier2CreditsByUserID: [String: Int] = [:]
    /// Mirrors `entitlements/{uid}.tier2ExpiresAt` — nil means no
    /// expiration recorded (never expires, matching the real adapter's
    /// tolerant treatment of a missing field).
    var tier2ExpiresAtByUserID: [String: Date] = [:]
    private var processedIdempotencyKeys: [String: (groupID: String, cookbookID: String)] = [:]

    /// Test/preview convenience — appends a group directly, bypassing
    /// createGroup's credit-spend requirement. Used to seed a fake MFB
    /// cookbook for join-gate tests.
    func seedGroup(_ group: FamilyGroup) {
        groups.append(group)
    }

    /// Test/preview convenience — appends a cookbook directly.
    func seedGroupCookbook(_ cookbook: GroupCookbook) {
        groupCookbooks.append(cookbook)
    }

    func createGroup(
        _ groupDetails: NewGroupDetails,
        cookbookDetails: NewGroupCookbookDetails,
        creatorUserID: String,
        creatorDisplayName: String,
        idempotencyKey: String
    ) async throws -> (FamilyGroup, GroupCookbook) {
        if let existing = processedIdempotencyKeys[idempotencyKey],
           let existingGroup = groups.first(where: { $0.id == existing.groupID }),
           let existingCookbook = groupCookbooks.first(where: { $0.id == existing.cookbookID }) {
            return (existingGroup, existingCookbook)
        }

        let availableCredits = tier2CreditsByUserID[creatorUserID] ?? 0
        guard availableCredits > 0 else {
            throw GroupsServiceError.insufficientCredits
        }
        if let expiresAt = tier2ExpiresAtByUserID[creatorUserID], expiresAt < .now {
            throw GroupsServiceError.creditExpired
        }

        let group = FamilyGroup(
            id: UUID().uuidString,
            slug: UUID().uuidString.lowercased(),
            name: groupDetails.name,
            description: groupDetails.description,
            type: groupDetails.type,
            locationText: groupDetails.locationText,
            structuredRegion: groupDetails.structuredRegion,
            coverImageURL: nil,
            visibility: groupDetails.visibility,
            createdByUserID: creatorUserID,
            createdByDisplayName: creatorDisplayName,
            createdAt: .now,
            status: .active,
            allowsMemberInvites: groupDetails.allowsMemberInvites,
            approvalPolicy: groupDetails.approvalPolicy,
            isMFB: false
        )
        let cookbook = GroupCookbook(
            id: UUID().uuidString,
            groupID: group.id,
            cookbookName: cookbookDetails.cookbookName,
            createdByUserID: creatorUserID,
            createdByDisplayName: creatorDisplayName,
            createdAt: .now,
            coverImageURL: nil,
            allowsMemberPublishing: cookbookDetails.allowsMemberPublishing
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

        tier2CreditsByUserID[creatorUserID] = availableCredits - 1
        groups.append(group)
        groupCookbooks.append(cookbook)
        upsertMembership(founderMembership)
        processedIdempotencyKeys[idempotencyKey] = (group.id, cookbook.id)

        return (group, cookbook)
    }

    func createGroupCookbook(
        _ details: NewGroupCookbookDetails,
        in groupID: String,
        creatorUserID: String,
        creatorDisplayName: String
    ) async throws -> GroupCookbook {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(creatorUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        let cookbook = GroupCookbook(
            id: UUID().uuidString,
            groupID: groupID,
            cookbookName: details.cookbookName,
            createdByUserID: creatorUserID,
            createdByDisplayName: creatorDisplayName,
            createdAt: .now,
            coverImageURL: nil,
            allowsMemberPublishing: details.allowsMemberPublishing
        )
        groupCookbooks.append(cookbook)
        return cookbook
    }

    func fetchGroupCookbooks(forGroup groupID: String) async throws -> [GroupCookbook] {
        groupCookbooks.filter { $0.groupID == groupID }
    }

    func fetchGroupCookbook(id: String) async throws -> GroupCookbook? {
        groupCookbooks.first { $0.id == id }
    }

    func fetchPublicGroupCookbooks(matching filter: PublicGroupCookbookSearchFilter) async throws -> [GroupCookbook] {
        let publicGroupIDs = Set(groups.filter { $0.visibility == .publicGroup && $0.status == .active }.map(\.id))
        var cookbooks = groupCookbooks.filter { publicGroupIDs.contains($0.groupID) }
        if let text = filter.text, !text.isEmpty {
            cookbooks = cookbooks.filter { $0.cookbookName.localizedCaseInsensitiveContains(text) }
        }
        return cookbooks
    }

    func fetchPublicGroups(matching filter: PublicGroupSearchFilter) async throws -> [FamilyGroup] {
        var publicGroups = groups.filter { $0.visibility == .publicGroup && $0.status == .active }
        if let text = filter.text, !text.isEmpty {
            publicGroups = publicGroups.filter { $0.name.localizedCaseInsensitiveContains(text) }
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

        if group.approvalPolicy == .noApprovalNeeded {
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

        guard let group = groups.first(where: { $0.id == request.groupID }) else {
            throw GroupsServiceError.groupNotFound
        }
        let groupMemberships = try await fetchMemberships(forGroup: request.groupID)
        guard GroupPolicy.canDecideJoinRequest(decidedByUserID, group: group, memberships: groupMemberships) else {
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
        groupCookbooks.removeAll { $0.groupID == groupID }
        memberships.removeAll { $0.groupID == groupID }
        joinRequests.removeAll { $0.groupID == groupID }
        invitations.removeAll { $0.groupID == groupID }
    }
}
