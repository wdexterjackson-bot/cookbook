//
//  GroupCookbook.swift
//  cookbook
//
//  Split out from FamilyGroup so one group can hold several cookbooks.
//  Cookbook visibility is all-or-nothing per group membership — there's no
//  per-cookbook membership, so `allowsMemberPublishing`/`commentsAllowed`
//  are the only things that vary per cookbook rather than per group (join
//  approval, which does gate membership, stays on
//  FamilyGroup.approvalPolicy instead).
//

import Foundation

struct GroupCookbook: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    var cookbookName: String
    var createdByUserID: String
    /// Snapshotted at creation time, same convention as
    /// `FamilyGroup.createdByDisplayName`.
    var createdByDisplayName: String
    var createdAt: Date
    var coverImageURL: String?
    /// Hex string (no leading #), same round-trip convention as
    /// `Cookbook.coverColorHex` — falls back to `Cookbook.defaultColorHex`
    /// wherever this is nil, which only ever happens for a cookbook
    /// created before this field existed (new ones always write it
    /// explicitly, see `FirestoreGroupsService.cookbookData`).
    var coverColorHex: String?
    /// A bundled CookbookCoverStyleCatalog design, same shared catalog
    /// `Cookbook.coverStyleImageName` uses — nil means none chosen. A
    /// custom `coverImageURL` always wins over this if both are set,
    /// same priority order as the personal-cookbook editor.
    var coverStyleImageName: String?
    /// Whether members (not just admins) can publish recipes to this
    /// specific cookbook — independent of which cookbooks in the group a
    /// member can even see (that's all-or-nothing, governed by group
    /// membership alone).
    var allowsMemberPublishing: Bool
    /// Cookbook-wide ceiling on `Publication.commentsEnabled` — a
    /// recipe's own per-publish "Allow Comments?" choice can only ever
    /// take effect if this is also true. Optional (not a plain `Bool`
    /// with a Swift-side default) because Firestore's Codable decoding
    /// throws on a genuinely missing key regardless of a compile-time
    /// default — a stored default only helps direct Swift construction,
    /// not `data(as:)` — so every read site treats `nil` as `true`
    /// ("on by default"), same as `FamilyGroup.isMFB`'s own optional-for-
    /// old-docs precedent. New cookbooks always write this explicitly
    /// (see `FirestoreGroupsService.cookbookData`), so `nil` only ever
    /// occurs for a cookbook created before this field existed.
    var commentsAllowed: Bool?
}
