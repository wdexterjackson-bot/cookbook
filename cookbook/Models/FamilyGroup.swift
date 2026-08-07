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

struct FamilyGroup: Codable, Identifiable, Equatable {
    var id: String
    var slug: String
    /// The family/group's own name (e.g. "Jackson") — distinct from
    /// `cookbookName`, which is this particular cookbook's display name
    /// (e.g. "Jackson Family Reunion 2020"). One family could plausibly
    /// have more than one cookbook someday; `name` + `cookbookName` +
    /// `locationText` together are what `uniquenessKey` guards.
    var name: String
    var cookbookName: String
    var description: String
    var type: String
    var locationText: String
    var structuredRegion: String?
    var coverImageURL: String?
    var visibility: GroupVisibility
    var createdByUserID: String
    var createdAt: Date
    var status: GroupStatus
    /// Default false per the PRD's recommendation — invites are admin-only
    /// unless a group explicitly opts in to letting any member invite.
    var allowsMemberInvites: Bool
    var allowsMemberPublishing: Bool
    /// When true, requestToJoin grants membership immediately instead of
    /// creating a JoinRequest an admin must approve — meant for a small
    /// number of intentionally open cookbooks (e.g. a global seed
    /// cookbook everyone's invited to), not the default for a family's
    /// own private/public cookbook.
    var autoApproveJoinRequests: Bool
}

extension FamilyGroup {
    /// Deterministic identity for the "Cookbook Name + Family/Group Name +
    /// Home Location must be unique" invariant — same reasoning as
    /// `Membership.compositeID`: rules can't run arbitrary queries, so
    /// uniqueness is enforced via a reservation doc keyed by this exact
    /// string (see `groupUniquenessKeys/{key}` in firestore.rules).
    /// Normalizes so "Jackson" and " jackson  " collide as intended.
    static func uniquenessKey(cookbookName: String, familyName: String, locationText: String) -> String {
        [cookbookName, familyName, locationText]
            .map(normalize)
            .joined(separator: "|")
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }
}
