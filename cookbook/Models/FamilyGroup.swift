//
//  FamilyGroup.swift
//  cookbook
//
//  Cloud-only per the Phase 2 scope decision — a plain Codable struct
//  round-tripped through Firestore, not a SwiftData @Model.
//

import Foundation

enum GroupVisibility: String, Codable {
    case publicGroup = "public"
    case privateGroup = "private"
}

enum GroupStatus: String, Codable {
    case active
    case archived
}

/// Governs both whether joining a group needs approval at all, and — when
/// it does — who is allowed to decide a pending JoinRequest. See
/// `firestore.rules`' `canDecideJoinRequest()` for the server-side
/// enforcement this must stay in lock-step with.
enum JoinApprovalPolicy: String, Codable {
    /// Only the group's own creator may decide.
    case creatorOnly
    /// Any active admin may decide (today's implicit behavior, made explicit).
    case anyAdministrator
    /// Any active member, not just admins, may decide.
    case anyUser
    /// No decision needed — requestToJoin grants membership immediately.
    /// Replaces the old `autoApproveJoinRequests` boolean.
    case noApprovalNeeded
}

struct FamilyGroup: Codable, Identifiable, Equatable {
    var id: String
    var slug: String
    /// The family/group's own name (e.g. "Jackson") — distinct from a
    /// `GroupCookbook.cookbookName` (e.g. "Jackson Family Reunion 2020").
    /// One family can now hold several cookbooks under the same group.
    var name: String
    var description: String
    var type: String
    var locationText: String
    var structuredRegion: String?
    var coverImageURL: String?
    var visibility: GroupVisibility
    var createdByUserID: String
    /// Snapshotted at creation time, same convention as
    /// `Recipe.authorLineage` — wherever a group is listed (search results,
    /// invitation cards), this shows who a viewer would be requesting
    /// from, without needing a general "look up any user's name"
    /// capability.
    var createdByDisplayName: String
    var createdAt: Date
    var status: GroupStatus
    /// Default false per the PRD's recommendation — invites are admin-only
    /// unless a group explicitly opts in to letting any member invite.
    var allowsMemberInvites: Bool
    var approvalPolicy: JoinApprovalPolicy
    /// The one hardcoded exception to the Pro User paywall (join gate) —
    /// true only for the single seeded MFB (Memphis Family Barrentine)
    /// cookbook. Deliberately NOT settable from the normal create-a-Family-
    /// Cookbook flow (every client-created group hardcodes this false);
    /// there is no in-app path that ever flips it true, by design — it's
    /// meant to be set once, directly in Firestore, on that one document.
    /// Optional so existing group documents predating this field decode
    /// safely as "not MFB" instead of failing to decode at all.
    var isMFB: Bool?
}
