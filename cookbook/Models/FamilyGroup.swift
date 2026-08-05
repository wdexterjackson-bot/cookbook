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
    var name: String
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
}
