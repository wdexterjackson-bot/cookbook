//
//  FirestoreGroupsService.swift
//  cookbook
//
//  Collections: groups/{id}, memberships/{id} (top-level, queried by
//  groupID/userID rather than nested — simpler cross-group membership
//  lookups), joinRequests/{id}, invitations/{id}, entitlements/{uid},
//  groupCreationRequests/{idempotencyKey} (the idempotency ledger for
//  createGroup — PAY-005).
//

import FirebaseFirestore
import FirebaseFunctions
import Foundation

final class FirestoreGroupsService: GroupsServicing {
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    func createGroup(_ details: NewGroupDetails, creatorUserID: String, idempotencyKey: String) async throws -> FamilyGroup {
        let requestRef = db.collection("groupCreationRequests").document(idempotencyKey)
        let entitlementRef = db.collection("entitlements").document(creatorUserID)
        let groupRef = db.collection("groups").document()
        let membershipRef = db.collection("memberships").document(Membership.compositeID(groupID: groupRef.documentID, userID: creatorUserID))
        let uniquenessKey = FamilyGroup.uniquenessKey(cookbookName: details.cookbookName, familyName: details.name, locationText: details.locationText)
        let uniquenessRef = db.collection("groupUniquenessKeys").document(uniquenessKey)

        let transactionResult: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let requestSnapshot = try transaction.getDocument(requestRef)
                if let existingGroupID = requestSnapshot.data()?["groupID"] as? String {
                    return existingGroupID
                }

                let entitlementSnapshot = try transaction.getDocument(entitlementRef)
                let tier2Credits = entitlementSnapshot.data()?["tier2Credits"] as? Int ?? 0
                guard tier2Credits > 0 else {
                    errorPointer?.pointee = GroupsServiceError.insufficientCredits as NSError
                    return nil
                }
                // Checked in the same transaction as the credit count
                // itself (not a separate pre-fetch) so this stays atomic
                // with the read it's judging — the rules-side
                // tier2NotExpired check is the real enforcement against a
                // client that skips this, this is just for a clean error.
                if let expiresAt = (entitlementSnapshot.data()?["tier2ExpiresAt"] as? Timestamp)?.dateValue(), expiresAt < Date() {
                    errorPointer?.pointee = GroupsServiceError.creditExpired as NSError
                    return nil
                }

                // Checked defensively for a clean error even though the
                // rules' create-vs-update semantics are the real
                // enforcement (see firestore.rules) — without this check
                // the transaction would still fail, just with a raw
                // permission-denied instead of a catchable Swift error.
                let uniquenessSnapshot = try transaction.getDocument(uniquenessRef)
                guard !uniquenessSnapshot.exists else {
                    errorPointer?.pointee = GroupsServiceError.duplicateCookbookIdentity as NSError
                    return nil
                }

                let now = Date()
                transaction.setData([
                    "tier2Credits": tier2Credits - 1,
                ], forDocument: entitlementRef, merge: true)

                transaction.setData(Self.groupData(details, id: groupRef.documentID, uniquenessKey: uniquenessKey, creatorUserID: creatorUserID, createdAt: now), forDocument: groupRef)
                transaction.setData(Self.founderMembershipData(id: membershipRef.documentID, groupID: groupRef.documentID, userID: creatorUserID, joinedAt: now), forDocument: membershipRef)
                transaction.setData(["groupID": groupRef.documentID, "requestedByUserID": creatorUserID, "createdAt": now], forDocument: requestRef)
                transaction.setData(["groupID": groupRef.documentID, "createdAt": now], forDocument: uniquenessRef)

                return groupRef.documentID
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let groupID = transactionResult as? String else {
            throw GroupsServiceError.groupNotFound
        }
        guard let group = try await fetchGroup(id: groupID) else {
            throw GroupsServiceError.groupNotFound
        }
        return group
    }

    func fetchPublicGroups(matching filter: PublicGroupSearchFilter) async throws -> [FamilyGroup] {
        let snapshot = try await db.collection("groups")
            .whereField("visibility", isEqualTo: GroupVisibility.publicGroup.rawValue)
            .whereField("status", isEqualTo: GroupStatus.active.rawValue)
            .getDocuments()
        var groups = try snapshot.documents.map { try $0.data(as: FamilyGroup.self) }

        if let text = filter.text, !text.isEmpty {
            groups = groups.filter {
                $0.cookbookName.localizedCaseInsensitiveContains(text) || $0.name.localizedCaseInsensitiveContains(text)
            }
        }
        if let locationText = filter.locationText, !locationText.isEmpty {
            groups = groups.filter { $0.locationText.localizedCaseInsensitiveContains(locationText) }
        }
        return groups
    }

    func fetchGroup(id: String) async throws -> FamilyGroup? {
        let snapshot = try await db.collection("groups").document(id).getDocument()
        return try snapshot.data(as: FamilyGroup.self)
    }

    func fetchMemberships(forGroup groupID: String) async throws -> [Membership] {
        let snapshot = try await db.collection("memberships").whereField("groupID", isEqualTo: groupID).getDocuments()
        return try snapshot.documents.map { try $0.data(as: Membership.self) }
    }

    func fetchMemberships(forUser userID: String) async throws -> [Membership] {
        let snapshot = try await db.collection("memberships").whereField("userID", isEqualTo: userID).getDocuments()
        return try snapshot.documents.map { try $0.data(as: Membership.self) }
    }

    func requestToJoin(groupID: String, requesterID: String, note: String?) async throws -> JoinRequest {
        guard let group = try await fetchGroup(id: groupID) else {
            throw GroupsServiceError.groupNotFound
        }
        let existingMemberships = try await fetchMemberships(forGroup: groupID)
        guard !GroupPolicy.isActiveMember(requesterID, in: existingMemberships) else {
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
            try db.collection("memberships").document(membership.id).setData(from: membership)
            // No JoinRequest document is written for this path — there's
            // nothing pending to record, and firestore.rules' joinRequests
            // create rule requires state == 'pending' anyway. The caller
            // still gets a JoinRequest value back so it doesn't need a
            // separate return type for this case.
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
            id: db.collection("joinRequests").document().documentID,
            groupID: groupID,
            requesterID: requesterID,
            note: note,
            state: .pending,
            decidedByUserID: nil,
            createdAt: .now,
            decidedAt: nil
        )
        try db.collection("joinRequests").document(request.id).setData(from: request)
        return request
    }

    func decideJoinRequest(_ requestID: String, approve: Bool, decidedByUserID: String) async throws {
        let ref = db.collection("joinRequests").document(requestID)
        let snapshot = try await ref.getDocument()
        guard var request = try snapshot.data(as: JoinRequest?.self) else {
            throw GroupsServiceError.joinRequestNotFound
        }
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
        try ref.setData(from: request)

        if approve {
            let membership = Membership(
                id: Membership.compositeID(groupID: request.groupID, userID: request.requesterID),
                groupID: request.groupID,
                userID: request.requesterID,
                role: .member,
                status: .active,
                source: .request,
                joinedAt: .now,
                leftAt: nil
            )
            try db.collection("memberships").document(membership.id).setData(from: membership)
        }
    }

    func fetchJoinRequests(forGroup groupID: String) async throws -> [JoinRequest] {
        let snapshot = try await db.collection("joinRequests")
            .whereField("groupID", isEqualTo: groupID)
            .whereField("state", isEqualTo: JoinRequestState.pending.rawValue)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: JoinRequest.self) }
    }

    func fetchJoinRequests(byRequester userID: String) async throws -> [JoinRequest] {
        let snapshot = try await db.collection("joinRequests")
            .whereField("requesterID", isEqualTo: userID)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: JoinRequest.self) }
    }

    func fetchInvitations(forInvitee identifier: String) async throws -> [Invitation] {
        let snapshot = try await db.collection("invitations")
            .whereField("inviteeIdentifier", isEqualTo: identifier)
            .whereField("state", isEqualTo: InvitationState.pending.rawValue)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: Invitation.self) }
    }

    func invite(groupID: String, inviterID: String, inviteeIdentifier: String, role: MembershipRole) async throws -> Invitation {
        guard let group = try await fetchGroup(id: groupID) else {
            throw GroupsServiceError.groupNotFound
        }
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        let canInvite = GroupPolicy.isActiveAdmin(inviterID, in: groupMemberships)
            || (group.allowsMemberInvites && GroupPolicy.isActiveMember(inviterID, in: groupMemberships))
        guard canInvite else {
            throw GroupsServiceError.notAuthorized
        }

        let invitation = Invitation(
            id: db.collection("invitations").document().documentID,
            groupID: groupID,
            inviterID: inviterID,
            inviteeIdentifier: inviteeIdentifier,
            role: role,
            tokenHash: NonceGenerator.sha256(UUID().uuidString),
            expiresAt: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now,
            state: .pending
        )
        try db.collection("invitations").document(invitation.id).setData(from: invitation)
        return invitation
    }

    func respondToInvitation(_ invitationID: String, accept: Bool, respondingUserID: String) async throws {
        let ref = db.collection("invitations").document(invitationID)
        let snapshot = try await ref.getDocument()
        guard var invitation = try snapshot.data(as: Invitation?.self) else {
            throw GroupsServiceError.invitationNotFound
        }
        guard invitation.state == .pending, invitation.expiresAt > .now else {
            throw GroupsServiceError.invalidState
        }

        invitation.state = accept ? .accepted : .declined
        try ref.setData(from: invitation)

        if accept {
            let membership = Membership(
                id: Membership.compositeID(groupID: invitation.groupID, userID: respondingUserID),
                groupID: invitation.groupID,
                userID: respondingUserID,
                role: invitation.role,
                status: .active,
                source: .invite,
                joinedAt: .now,
                leftAt: nil
            )
            try db.collection("memberships").document(membership.id).setData(from: membership)
        }
    }

    func updateRole(groupID: String, userID: String, newRole: MembershipRole, actingUserID: String) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        guard var membership = groupMemberships.first(where: { $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        if newRole == .member, GroupPolicy.isLastActiveAdmin(userID, in: groupMemberships) {
            throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
        }
        membership.role = newRole
        try db.collection("memberships").document(membership.id).setData(from: membership)
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
        guard var membership = groupMemberships.first(where: { $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        membership.status = .left
        membership.leftAt = .now
        try db.collection("memberships").document(membership.id).setData(from: membership)
    }

    /// Every client-facing collection touched here (`memberships`,
    /// `publications`, `groupUniquenessKeys`, `groups`) has
    /// `allow delete: if false` in firestore.rules, and storage.rules only
    /// lets a user delete files they themselves uploaded — so none of this
    /// cleanup is possible directly from the client. The Cloud Function
    /// runs with the Admin SDK, which bypasses both rules files.
    func deleteGroupPermanently(groupID: String) async throws {
        let callable = functions.httpsCallable("deleteGroupPermanently")
        _ = try await callable.call(["groupID": groupID])
    }

    /// `uniquenessKey` is written onto the group document (though not part
    /// of the `FamilyGroup` Swift model — nothing client-side reads it
    /// back) purely so firestore.rules' `groups` create rule can
    /// `getAfter()`-check it against the matching `groupUniquenessKeys/{key}`
    /// reservation doc written in the same transaction.
    private static func groupData(_ details: NewGroupDetails, id: String, uniquenessKey: String, creatorUserID: String, createdAt: Date) -> [String: Any] {
        [
            "id": id,
            "slug": UUID().uuidString.lowercased(),
            "name": details.name,
            "cookbookName": details.cookbookName,
            "uniquenessKey": uniquenessKey,
            "description": details.description,
            "type": details.type,
            "locationText": details.locationText,
            "structuredRegion": details.structuredRegion as Any,
            "coverImageURL": NSNull(),
            "visibility": details.visibility.rawValue,
            "createdByUserID": creatorUserID,
            "createdAt": createdAt,
            "status": GroupStatus.active.rawValue,
            "allowsMemberInvites": details.allowsMemberInvites,
            "allowsMemberPublishing": details.allowsMemberPublishing,
            "autoApproveJoinRequests": details.autoApproveJoinRequests,
            // Never settable from the normal create flow — see
            // FamilyGroup.isMFB's doc comment.
            "isMFB": false,
        ]
    }

    private static func founderMembershipData(id: String, groupID: String, userID: String, joinedAt: Date) -> [String: Any] {
        [
            "id": id,
            "groupID": groupID,
            "userID": userID,
            "role": MembershipRole.admin.rawValue,
            "status": MembershipStatus.active.rawValue,
            "source": MembershipSource.founder.rawValue,
            "joinedAt": joinedAt,
            "leftAt": NSNull(),
        ]
    }
}
