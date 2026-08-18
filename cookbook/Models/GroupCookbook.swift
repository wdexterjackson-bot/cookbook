//
//  GroupCookbook.swift
//  cookbook
//
//  Split out from FamilyGroup so one group can hold several cookbooks.
//  Cookbook visibility is all-or-nothing per group membership — there's no
//  per-cookbook membership, so `allowsMemberPublishing` is the only thing
//  that varies per cookbook rather than per group (join approval, which
//  does gate membership, stays on FamilyGroup.approvalPolicy instead).
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
    /// No upload path yet — same accepted gap as `FamilyGroup.coverImageURL`
    /// has today, not a regression introduced here.
    var coverImageURL: String?
    /// Whether members (not just admins) can publish recipes to this
    /// specific cookbook — independent of which cookbooks in the group a
    /// member can even see (that's all-or-nothing, governed by group
    /// membership alone).
    var allowsMemberPublishing: Bool
}
