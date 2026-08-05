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
}

struct NewGroupDetails {
    var name: String
    var description: String
    var type: String
    var locationText: String
    var structuredRegion: String?
    var visibility: GroupVisibility
    var allowsMemberInvites: Bool
    var allowsMemberPublishing: Bool
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

    func fetchPublicGroups(matching query: String?) async throws -> [FamilyGroup]
    func fetchGroup(id: String) async throws -> FamilyGroup?
    func fetchMemberships(forGroup groupID: String) async throws -> [Membership]
    func fetchMemberships(forUser userID: String) async throws -> [Membership]

    func requestToJoin(groupID: String, requesterID: String, note: String?) async throws -> JoinRequest
    func decideJoinRequest(_ requestID: String, approve: Bool, decidedByUserID: String) async throws

    func invite(groupID: String, inviterID: String, inviteeIdentifier: String, role: MembershipRole) async throws -> Invitation
    func respondToInvitation(_ invitationID: String, accept: Bool, respondingUserID: String) async throws

    /// Throws `.lastAdminCannotLeaveOrBeDemoted` if this would leave the
    /// group with no active admin (GRP-008).
    func updateRole(groupID: String, userID: String, newRole: MembershipRole, actingUserID: String) async throws
    /// Throws `.lastAdminCannotLeaveOrBeDemoted` under the same rule.
    func leaveGroup(groupID: String, userID: String) async throws
    func archiveGroup(groupID: String, actingUserID: String) async throws
}
