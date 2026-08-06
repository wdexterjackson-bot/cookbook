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
    /// Throws `.lastAdminCannotLeaveOrBeDemoted` under the same rule.
    func leaveGroup(groupID: String, userID: String) async throws
    func archiveGroup(groupID: String, actingUserID: String) async throws
}
