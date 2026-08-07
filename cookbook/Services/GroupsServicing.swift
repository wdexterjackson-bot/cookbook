//
//  GroupsServicing.swift
//  cookbook
//
//  The seam for everything a group's lifecycle touches: the group itself,
//  its memberships, join requests, and invitations. These four are one
//  protocol (not four) because they're one aggregate — nothing here makes
//  sense without the others.
//

import Foundation

enum GroupsServiceError: Error, Equatable {
    case insufficientCredits
    case groupNotFound
    case membershipNotFound
    case joinRequestNotFound
    case invitationNotFound
    case notAuthorized
    case lastAdminCannotLeaveOrBeDemoted
    case alreadyMember
    case invalidState
    /// The Cookbook Name + Family/Group Name + Home Location combination
    /// is already taken by another group (FamilyGroup.uniquenessKey).
    case duplicateCookbookIdentity
}

struct NewGroupDetails {
    var name: String
    var cookbookName: String
    var description: String
    var type: String
    var locationText: String
    var structuredRegion: String?
    var visibility: GroupVisibility
    var allowsMemberInvites: Bool
    var allowsMemberPublishing: Bool
    var autoApproveJoinRequests: Bool
}

/// Search/filter for the public-cookbook-directory screen — `text` matches
/// against either `cookbookName` or `name` (family/group name), so
/// searching "Jackson" finds a cookbook named that OR a family named that;
/// `locationText` narrows further, matching the user's own "hundreds of
/// Team USA cookbooks, filter by family name and location" example.
struct PublicGroupSearchFilter {
    var text: String?
    var locationText: String?

    init(text: String? = nil, locationText: String? = nil) {
        self.text = text
        self.locationText = locationText
    }
}

/// Pure authorization/invariant checks shared by every GroupsServicing
/// conformer, so the real Firestore adapter and the in-memory test fake
/// can't drift on what "admin" or "last admin" means.
enum GroupPolicy {
    static func isActiveAdmin(_ userID: String, in memberships: [Membership]) -> Bool {
        memberships.contains { $0.userID == userID && $0.role == .admin && $0.status == .active }
    }

    static func isActiveMember(_ userID: String, in memberships: [Membership]) -> Bool {
        memberships.contains { $0.userID == userID && $0.status == .active }
    }

    static func isLastActiveAdmin(_ userID: String, in memberships: [Membership]) -> Bool {
        let activeAdmins = memberships.filter { $0.role == .admin && $0.status == .active }
        return activeAdmins.count == 1 && activeAdmins.first?.userID == userID
    }

    /// True when `userID` is the only active membership left, of any role —
    /// distinct from `isLastActiveAdmin`, which only looks at admins. This
    /// is the case where leaving deletes the whole group rather than just
    /// marking one membership `.left`.
    static func isLastActiveMember(_ userID: String, in memberships: [Membership]) -> Bool {
        let active = memberships.filter { $0.status == .active }
        return active.count == 1 && active.first?.userID == userID
    }
}

protocol GroupsServicing {
    /// Creates a group and its founding admin membership, consuming one
    /// creation credit — atomically and exactly once per `idempotencyKey`,
    /// even if this is called more than once for the same user action
    /// (PAY-005).
    func createGroup(_ details: NewGroupDetails, creatorUserID: String, idempotencyKey: String) async throws -> FamilyGroup

    func fetchPublicGroups(matching filter: PublicGroupSearchFilter) async throws -> [FamilyGroup]
    func fetchGroup(id: String) async throws -> FamilyGroup?
    func fetchMemberships(forGroup groupID: String) async throws -> [Membership]
    func fetchMemberships(forUser userID: String) async throws -> [Membership]

    func requestToJoin(groupID: String, requesterID: String, note: String?) async throws -> JoinRequest
    func decideJoinRequest(_ requestID: String, approve: Bool, decidedByUserID: String) async throws
    /// Join requests awaiting decision by an admin of `groupID`.
    func fetchJoinRequests(forGroup groupID: String) async throws -> [JoinRequest]
    /// Every join request `userID` has made, across all groups — used to
    /// show "your request was approved/denied" in Messages.
    func fetchJoinRequests(byRequester userID: String) async throws -> [JoinRequest]

    func invite(groupID: String, inviterID: String, inviteeIdentifier: String, role: MembershipRole) async throws -> Invitation
    func respondToInvitation(_ invitationID: String, accept: Bool, respondingUserID: String) async throws
    /// Pending invitations addressed to `identifier` (the invitee's email).
    func fetchInvitations(forInvitee identifier: String) async throws -> [Invitation]

    /// Throws `.lastAdminCannotLeaveOrBeDemoted` if this would leave the
    /// group with no active admin (GRP-008).
    func updateRole(groupID: String, userID: String, newRole: MembershipRole, actingUserID: String) async throws
    /// If `userID` is the last active member of any role, this deletes the
    /// group and everything in it (see `deleteGroupPermanently`) instead of
    /// just marking their membership `.left`. Otherwise throws
    /// `.lastAdminCannotLeaveOrBeDemoted` under the same rule as before —
    /// a populated-but-adminless group is still not allowed.
    func leaveGroup(groupID: String, userID: String) async throws
    /// Permanently deletes a group and everything tied to it — memberships,
    /// published recipes, their photos, and the cookbook-name/location
    /// reservation. Client-side rules block direct deletes on every one of
    /// those collections (`allow delete: if false`), so this always goes
    /// through a Cloud Function running with elevated privileges; there is
    /// no client-only implementation. Called automatically by `leaveGroup`
    /// when the leaving member is the last one — not normally called
    /// directly by UI code.
    func deleteGroupPermanently(groupID: String) async throws
}
