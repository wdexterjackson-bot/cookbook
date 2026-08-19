//
//  GroupsServicing.swift
//  cookbook
//
//  The seam for everything a group's lifecycle touches: the group itself,
//  its cookbooks, memberships, join requests, and invitations. These are
//  one protocol (not several) because they're one aggregate — nothing
//  here makes sense without the others.
//

import Foundation

enum GroupsServiceError: Error, Equatable {
    case insufficientCredits
    /// The account has a tier-2 credit on paper, but it's past
    /// `Entitlement.tier2ExpiresAt` — thrown by a client-side pre-check so
    /// this surfaces as a clean, catchable error instead of an opaque
    /// Firestore permission-denied from the rules-side enforcement.
    case creditExpired
    case groupNotFound
    case groupCookbookNotFound
    case membershipNotFound
    case joinRequestNotFound
    case invitationNotFound
    case notAuthorized
    case lastAdminCannotLeaveOrBeDemoted
    case alreadyMember
    case invalidState
    case joinRequestAlreadyPending
}

extension GroupsServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .insufficientCredits: return "You don't have a credit available for this."
        case .creditExpired: return "That credit has expired."
        case .groupNotFound: return "That cookbook group isn't there anymore."
        case .groupCookbookNotFound: return "That cookbook isn't there anymore."
        case .membershipNotFound: return "That membership isn't there anymore."
        case .joinRequestNotFound: return "That join request isn't there anymore."
        case .invitationNotFound: return "That invitation isn't there anymore."
        case .notAuthorized: return "You don't have permission to do that."
        case .lastAdminCannotLeaveOrBeDemoted: return "You're the last administrator — promote someone else first."
        case .alreadyMember: return "You're already a member of this group."
        case .invalidState: return "That action isn't available right now."
        case .joinRequestAlreadyPending: return "You already have a pending request to join this group."
        }
    }
}

struct NewGroupDetails {
    var name: String
    var description: String
    var type: String
    var locationText: String
    var structuredRegion: String?
    var visibility: GroupVisibility
    var allowsMemberInvites: Bool
    var approvalPolicy: JoinApprovalPolicy
}

struct NewGroupCookbookDetails {
    var cookbookName: String
    var allowsMemberPublishing: Bool
}

/// Search/filter for the public-group-directory screen — `text` matches
/// against `name` (the family/group name); `locationText` narrows further.
/// Cookbook-name search is a separate query now that a group's cookbooks
/// are their own objects — see `fetchPublicGroupCookbooks`.
struct PublicGroupSearchFilter {
    var text: String?
    var locationText: String?

    init(text: String? = nil, locationText: String? = nil) {
        self.text = text
        self.locationText = locationText
    }
}

struct PublicGroupCookbookSearchFilter {
    var text: String?

    init(text: String? = nil) {
        self.text = text
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

    /// Who is allowed to decide a pending JoinRequest, per the group's
    /// approvalPolicy. Must stay in lock-step with firestore.rules'
    /// canDecideJoinRequest() — a decide this allows but the rules reject
    /// (or vice versa) means either a legitimate admin gets a confusing
    /// permission-denied, or a client that skips this check gets away with
    /// something the rules alone should have caught. `.noApprovalNeeded`
    /// never produces a pending request in the first place (requestToJoin
    /// grants membership directly), so there's nothing to decide.
    static func canDecideJoinRequest(_ userID: String, group: FamilyGroup, memberships: [Membership]) -> Bool {
        switch group.approvalPolicy {
        case .creatorOnly:
            if isActiveMember(group.createdByUserID, in: memberships) {
                return userID == group.createdByUserID
            }
            // Fallback once the creator is no longer an active member —
            // must stay in lock-step with firestore.rules' matching
            // fallback in canDecideJoinRequest(), see its comment.
            return isActiveAdmin(userID, in: memberships)
        case .anyAdministrator:
            return isActiveAdmin(userID, in: memberships)
        case .anyUser:
            return isActiveMember(userID, in: memberships)
        case .noApprovalNeeded:
            return false
        }
    }
}

protocol GroupsServicing {
    /// Creates a group, its founding admin membership, and its first
    /// cookbook — atomically and exactly once per `idempotencyKey`, even
    /// if this is called more than once for the same user action
    /// (PAY-005). Consumes one tier-2 creation credit.
    func createGroup(
        _ groupDetails: NewGroupDetails,
        cookbookDetails: NewGroupCookbookDetails,
        creatorUserID: String,
        creatorDisplayName: String,
        idempotencyKey: String
    ) async throws -> (FamilyGroup, GroupCookbook)

    /// Adds a further cookbook to an already-existing group. Caller must
    /// already be an active admin of `groupID`.
    func createGroupCookbook(
        _ details: NewGroupCookbookDetails,
        in groupID: String,
        creatorUserID: String,
        creatorDisplayName: String
    ) async throws -> GroupCookbook

    func fetchGroupCookbooks(forGroup groupID: String) async throws -> [GroupCookbook]
    func fetchGroupCookbook(id: String) async throws -> GroupCookbook?
    /// Cookbook-name search across every cookbook belonging to a public,
    /// active group — a separate query from `fetchPublicGroups` now that
    /// cookbooks are their own objects (today's one search box finding
    /// either the group name or the cookbook name doesn't carry over
    /// as a single query post-split).
    func fetchPublicGroupCookbooks(matching filter: PublicGroupCookbookSearchFilter) async throws -> [GroupCookbook]

    func fetchPublicGroups(matching filter: PublicGroupSearchFilter) async throws -> [FamilyGroup]
    func fetchGroup(id: String) async throws -> FamilyGroup?
    func fetchMemberships(forGroup groupID: String) async throws -> [Membership]
    func fetchMemberships(forUser userID: String) async throws -> [Membership]

    func requestToJoin(groupID: String, requesterID: String, note: String?) async throws -> JoinRequest
    func decideJoinRequest(_ requestID: String, approve: Bool, decidedByUserID: String) async throws
    /// Join requests awaiting decision, for whoever has standing to decide
    /// them under `groupID`'s approvalPolicy.
    func fetchJoinRequests(forGroup groupID: String) async throws -> [JoinRequest]
    /// Every join request `userID` has made, across all groups — used to
    /// show "your request was approved/denied" in Messages.
    func fetchJoinRequests(byRequester userID: String) async throws -> [JoinRequest]

    func invite(groupID: String, inviterID: String, inviteeIdentifier: String, role: MembershipRole) async throws -> Invitation
    func respondToInvitation(_ invitationID: String, accept: Bool, respondingUserID: String) async throws
    /// Pending invitations addressed to `identifier` (the invitee's email
    /// or userID — see the invitations UID-matching fix in firestore.rules).
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
    /// An admin evicting someone else — unlike `leaveGroup`, this can't
    /// target the acting user themselves (use `leaveGroup`/`updateRole`
    /// for self-service). Marks the membership `.suspended` (distinct from
    /// a voluntary `.left`) but doesn't ban them permanently: they can
    /// still be re-invited or file a fresh join request afterward, same as
    /// anyone else who isn't currently a member. Throws
    /// `.lastAdminCannotLeaveOrBeDemoted` if `userID` is the group's last
    /// active admin (GRP-008), same invariant as `updateRole`/`leaveGroup`.
    func removeMember(groupID: String, userID: String, actingUserID: String) async throws
    /// Permanently deletes a group and everything tied to it — memberships,
    /// cookbooks, published recipes, and their photos. Client-side rules
    /// block direct deletes on every one of those collections
    /// (`allow delete: if false`), so this always goes through a Cloud
    /// Function running with elevated privileges; there is no client-only
    /// implementation. Called automatically by `leaveGroup` when the
    /// leaving member is the last one — not normally called directly by UI
    /// code.
    func deleteGroupPermanently(groupID: String) async throws
}
