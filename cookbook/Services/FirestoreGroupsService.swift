//
//  FirestoreGroupsService.swift
//  cookbook
//
//  Collections: groups/{id}, groupCookbooks/{id}, memberships/{id}
//  (top-level, queried by groupID/userID rather than nested — simpler
//  cross-group membership lookups), joinRequests/{id}, invitations/{id},
//  entitlements/{uid}, groupCreationRequests/{idempotencyKey} (the
//  idempotency ledger for createGroup — PAY-005).
//

import FirebaseFirestore
import FirebaseFunctions
import Foundation

final class FirestoreGroupsService: GroupsServicing {
    private let db = Firestore.firestore()
    private let functions = Functions.functions()

    func createGroup(
        _ groupDetails: NewGroupDetails,
        cookbookDetails: NewGroupCookbookDetails,
        creatorUserID: String,
        creatorDisplayName: String,
        idempotencyKey: String
    ) async throws -> (FamilyGroup, GroupCookbook) {
        let requestRef = db.collection("groupCreationRequests").document(idempotencyKey)
        let entitlementRef = db.collection("entitlements").document(creatorUserID)
        let groupRef = db.collection("groups").document()
        let cookbookRef = db.collection("groupCookbooks").document()
        let membershipRef = db.collection("memberships").document(Membership.compositeID(groupID: groupRef.documentID, userID: creatorUserID))

        let transactionResult: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let requestSnapshot = try transaction.getDocument(requestRef)
                if let existingGroupID = requestSnapshot.data()?["groupID"] as? String,
                   let existingCookbookID = requestSnapshot.data()?["cookbookID"] as? String {
                    return [existingGroupID, existingCookbookID]
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

                let now = Date()
                transaction.setData([
                    "tier2Credits": tier2Credits - 1,
                ], forDocument: entitlementRef, merge: true)

                transaction.setData(Self.groupData(groupDetails, id: groupRef.documentID, creatorUserID: creatorUserID, creatorDisplayName: creatorDisplayName, createdAt: now), forDocument: groupRef)
                transaction.setData(Self.cookbookData(cookbookDetails, id: cookbookRef.documentID, groupID: groupRef.documentID, creatorUserID: creatorUserID, creatorDisplayName: creatorDisplayName, createdAt: now), forDocument: cookbookRef)
                transaction.setData(Self.founderMembershipData(id: membershipRef.documentID, groupID: groupRef.documentID, userID: creatorUserID, joinedAt: now), forDocument: membershipRef)
                transaction.setData(["groupID": groupRef.documentID, "cookbookID": cookbookRef.documentID, "requestedByUserID": creatorUserID, "createdAt": now], forDocument: requestRef)

                return [groupRef.documentID, cookbookRef.documentID]
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let ids = transactionResult as? [String], ids.count == 2 else {
            throw GroupsServiceError.groupNotFound
        }
        guard let group = try await fetchGroup(id: ids[0]) else {
            throw GroupsServiceError.groupNotFound
        }
        guard let cookbook = try await fetchGroupCookbook(id: ids[1]) else {
            throw GroupsServiceError.groupCookbookNotFound
        }
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
            id: db.collection("groupCookbooks").document().documentID,
            groupID: groupID,
            cookbookName: details.cookbookName,
            createdByUserID: creatorUserID,
            createdByDisplayName: creatorDisplayName,
            createdAt: .now,
            coverImageURL: nil,
            allowsMemberPublishing: details.allowsMemberPublishing
        )
        try db.collection("groupCookbooks").document(cookbook.id).setData(from: cookbook)
        return cookbook
    }

    func fetchGroupCookbooks(forGroup groupID: String) async throws -> [GroupCookbook] {
        let snapshot = try await db.collection("groupCookbooks").whereField("groupID", isEqualTo: groupID).getDocuments()
        return try snapshot.documents.map { try $0.data(as: GroupCookbook.self) }
    }

    func fetchGroupCookbook(id: String) async throws -> GroupCookbook? {
        let snapshot = try await db.collection("groupCookbooks").document(id).getDocument()
        return try snapshot.data(as: GroupCookbook.self)
    }

    /// Fetches every cookbook belonging to a public, active group, then
    /// filters by name client-side — mirrors `fetchPublicGroups`' own
    /// "fetch broadly, filter in Swift" style rather than a dedicated
    /// search backend. `whereField(_:in:)` caps at 30 values per query, so
    /// group IDs are chunked; fine at this app's actual scale, would need
    /// revisiting for a much larger public-group directory.
    func fetchPublicGroupCookbooks(matching filter: PublicGroupCookbookSearchFilter) async throws -> [GroupCookbook] {
        let publicGroups = try await fetchPublicGroups(matching: PublicGroupSearchFilter())
        guard !publicGroups.isEmpty else { return [] }
        let groupIDs = publicGroups.map(\.id)

        var cookbooks: [GroupCookbook] = []
        for chunkStart in stride(from: 0, to: groupIDs.count, by: 30) {
            let chunk = Array(groupIDs[chunkStart..<min(chunkStart + 30, groupIDs.count)])
            let snapshot = try await db.collection("groupCookbooks").whereField("groupID", in: chunk).getDocuments()
            cookbooks += try snapshot.documents.map { try $0.data(as: GroupCookbook.self) }
        }

        if let text = filter.text, !text.isEmpty {
            cookbooks = cookbooks.filter { $0.cookbookName.localizedCaseInsensitiveContains(text) }
        }
        return cookbooks
    }

    func fetchPublicGroups(matching filter: PublicGroupSearchFilter) async throws -> [FamilyGroup] {
        let snapshot = try await db.collection("groups")
            .whereField("visibility", isEqualTo: GroupVisibility.publicGroup.rawValue)
            .whereField("status", isEqualTo: GroupStatus.active.rawValue)
            .getDocuments()
        var groups = try snapshot.documents.map { try $0.data(as: FamilyGroup.self) }

        if let text = filter.text, !text.isEmpty {
            groups = groups.filter { $0.name.localizedCaseInsensitiveContains(text) }
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

    func fetchMFBGroup() async throws -> FamilyGroup? {
        // visibility == public is included so this query is provable
        // under groups/read's rule (`visibility == 'public' || isMember`)
        // without needing isMember for every possible match — same
        // reasoning fetchPublicGroups already relies on.
        let snapshot = try await db.collection("groups")
            .whereField("visibility", isEqualTo: GroupVisibility.publicGroup.rawValue)
            .whereField("isMFB", isEqualTo: true)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first.map { try $0.data(as: FamilyGroup.self) }
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

        // Deterministic id so a second request from this person for this
        // group lands on the same document — rejected outright while still
        // pending, or reset to a fresh pending request otherwise (denied,
        // cancelled, expired, or approved-then-later-removed — the
        // isActiveMember guard above already ruled out "still an active
        // member") — instead of creating a duplicate doc an admin would see
        // as two separate rows, one of them stuck pending forever.
        let requestID = JoinRequest.compositeID(groupID: groupID, requesterID: requesterID)
        let requestRef = db.collection("joinRequests").document(requestID)
        if let existing = try await requestRef.getDocument().data(as: JoinRequest?.self), existing.state == .pending {
            throw GroupsServiceError.joinRequestAlreadyPending
        }

        let request = JoinRequest(
            id: requestID,
            groupID: groupID,
            requesterID: requesterID,
            note: note,
            state: .pending,
            decidedByUserID: nil,
            createdAt: .now,
            decidedAt: nil
        )
        try requestRef.setData(from: request)
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

        guard let group = try await fetchGroup(id: request.groupID) else {
            throw GroupsServiceError.groupNotFound
        }
        let groupMemberships = try await fetchMemberships(forGroup: request.groupID)
        guard GroupPolicy.canDecideJoinRequest(decidedByUserID, group: group, memberships: groupMemberships) else {
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

    func updateGroup(
        _ groupID: String,
        name: String,
        locationText: String,
        visibility: GroupVisibility,
        approvalPolicy: JoinApprovalPolicy,
        allowsMemberInvites: Bool,
        actingUserID: String
    ) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        try await db.collection("groups").document(groupID).updateData([
            "name": name,
            "locationText": locationText,
            "visibility": visibility.rawValue,
            "approvalPolicy": approvalPolicy.rawValue,
            "allowsMemberInvites": allowsMemberInvites,
        ])
    }

    func updateGroupCookbook(
        _ cookbookID: String,
        groupID: String,
        cookbookName: String,
        allowsMemberPublishing: Bool,
        commentsAllowed: Bool,
        coverColorHex: String,
        coverStyleImageName: String?,
        coverImageURL: String?,
        actingUserID: String
    ) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        try await db.collection("groupCookbooks").document(cookbookID).updateData([
            "cookbookName": cookbookName,
            "allowsMemberPublishing": allowsMemberPublishing,
            "commentsAllowed": commentsAllowed,
            "coverColorHex": coverColorHex,
            "coverStyleImageName": coverStyleImageName as Any? ?? NSNull(),
            "coverImageURL": coverImageURL as Any? ?? NSNull(),
        ])
    }

    func updateRole(groupID: String, userID: String, newRole: MembershipRole, actingUserID: String) async throws {
        let groupMemberships = try await fetchMemberships(forGroup: groupID)
        guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
            throw GroupsServiceError.notAuthorized
        }
        guard let membership = groupMemberships.first(where: { $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        // Self-demotion no longer writes directly — firestore.rules'
        // memberships/update rule excludes self-targeting from the
        // "admin changing someone's role" branch entirely, since rules
        // can't cheaply verify another admin remains. changeOwnMembership
        // (Admin SDK) does that check server-side instead. There's no
        // realistic self-target-to-.admin case (you're already admin to
        // call this at all), so that's a no-op rather than a write.
        if userID == actingUserID {
            if newRole == .admin { return }
            if newRole == .member, GroupPolicy.isLastActiveAdmin(userID, in: groupMemberships) {
                throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
            }
            try await changeOwnMembership(groupID: groupID, action: "demote")
            return
        }
        // Routed through the changeMemberRole Cloud Function, not a direct
        // Firestore write — a plain read-then-write here (what this used
        // to be) lets two admins simultaneously demoting/removing *each
        // other* both read "2 active admins, safe to proceed" and both
        // commit, leaving zero active admins with no way to ever create
        // another (promoting requires being one). The client Firestore
        // SDK's Transaction type has no query support (only
        // get(DocumentReference)), so this can't be closed with a client-
        // side transaction the way it first looked like it could — only
        // the Admin SDK's Transaction.get() accepts a Query, hence a
        // Cloud Function, same reasoning as changeOwnMembership.js.
        try await changeMemberRole(groupID: groupID, targetUserID: userID, action: newRole == .admin ? "promote" : "demote")
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
        guard let membership = groupMemberships.first(where: { $0.userID == userID && $0.status == .active }) else {
            throw GroupsServiceError.membershipNotFound
        }
        // Same reasoning as updateRole above: an active admin leaving no
        // longer writes directly (firestore.rules now requires
        // resource.data.role == 'member' on the self-leave branch) — only
        // a plain member's own leave stays a direct write.
        if membership.role == .admin {
            try await changeOwnMembership(groupID: groupID, action: "leave")
            return
        }
        var mutableMembership = membership
        mutableMembership.status = .left
        mutableMembership.leftAt = .now
        try db.collection("memberships").document(mutableMembership.id).setData(from: mutableMembership)
    }

    /// Backs the two self-targeting membership mutations firestore.rules
    /// can no longer allow as a direct client write (self-leave-as-admin,
    /// self-demote) — see changeOwnMembership.js for why rules alone
    /// can't enforce "the last admin can't leave or be demoted."
    private func changeOwnMembership(groupID: String, action: String) async throws {
        let callable = functions.httpsCallable("changeOwnMembership")
        do {
            _ = try await callable.call(["groupID": groupID, "action": action])
        } catch {
            // The client-side pre-checks in updateRole/leaveGroup can be
            // fooled by a stale membership snapshot (another admin was
            // just demoted/removed by someone else, list not yet
            // refreshed) — when that happens, this callable's own
            // server-side re-verification is what actually rejects it,
            // and without this remap that surfaced as a generic Firebase
            // Functions error instead of the same friendly message the
            // common case already shows.
            throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
        }
    }

    /// Backs an admin promoting/demoting/removing *someone else* —
    /// see functions/changeMemberRole.js for why this needs a Cloud
    /// Function rather than a client-side transaction. Same blanket
    /// remap-on-failure reasoning as changeOwnMembership above: by the
    /// time this is called, updateRole/removeMember's own pre-checks
    /// already passed against the client's local membership snapshot, so
    /// the only realistic way this callable itself then rejects is that
    /// snapshot having gone stale (someone else's role/status changed a
    /// moment ago) — which is exactly the "last admin" family of error
    /// the UI already has a friendly message for.
    private func changeMemberRole(groupID: String, targetUserID: String, action: String) async throws {
        let callable = functions.httpsCallable("changeMemberRole")
        do {
            _ = try await callable.call(["groupID": groupID, "targetUserID": targetUserID, "action": action])
        } catch {
            throw GroupsServiceError.lastAdminCannotLeaveOrBeDemoted
        }
    }

    func removeMember(groupID: String, userID: String, actingUserID: String) async throws {
        guard userID != actingUserID else {
            throw GroupsServiceError.notAuthorized
        }
        // Routed through changeMemberRole for the same reason as
        // updateRole's "someone else" branch above — see its comment.
        try await changeMemberRole(groupID: groupID, targetUserID: userID, action: "remove")
    }

    /// Every client-facing collection touched here (`memberships`,
    /// `publications`, `groupCookbooks`, `groups`) has
    /// `allow delete: if false` in firestore.rules, and storage.rules only
    /// lets a user delete files they themselves uploaded — so none of this
    /// cleanup is possible directly from the client. The Cloud Function
    /// runs with the Admin SDK, which bypasses both rules files.
    func deleteGroupPermanently(groupID: String) async throws {
        let callable = functions.httpsCallable("deleteGroupPermanently")
        _ = try await callable.call(["groupID": groupID])
    }

    private static func groupData(_ details: NewGroupDetails, id: String, creatorUserID: String, creatorDisplayName: String, createdAt: Date) -> [String: Any] {
        [
            "id": id,
            "slug": UUID().uuidString.lowercased(),
            "name": details.name,
            "description": details.description,
            "type": details.type,
            "locationText": details.locationText,
            "structuredRegion": details.structuredRegion as Any,
            "coverImageURL": NSNull(),
            "visibility": details.visibility.rawValue,
            "createdByUserID": creatorUserID,
            "createdByDisplayName": creatorDisplayName,
            "createdAt": createdAt,
            "status": GroupStatus.active.rawValue,
            "allowsMemberInvites": details.allowsMemberInvites,
            "approvalPolicy": details.approvalPolicy.rawValue,
            // Never settable from the normal create flow — see
            // FamilyGroup.isMFB's doc comment.
            "isMFB": false,
        ]
    }

    private static func cookbookData(_ details: NewGroupCookbookDetails, id: String, groupID: String, creatorUserID: String, creatorDisplayName: String, createdAt: Date) -> [String: Any] {
        [
            "id": id,
            "groupID": groupID,
            "cookbookName": details.cookbookName,
            "createdByUserID": creatorUserID,
            "createdByDisplayName": creatorDisplayName,
            "createdAt": createdAt,
            "coverImageURL": NSNull(),
            "allowsMemberPublishing": details.allowsMemberPublishing,
            "commentsAllowed": true,
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
