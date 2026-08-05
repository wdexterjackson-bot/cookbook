//
//  Membership.swift
//  cookbook
//

import Foundation

enum MembershipRole: String, Codable {
    case member
    case admin
}

enum MembershipStatus: String, Codable {
    case active
    case left
    case suspended
}

enum MembershipSource: String, Codable {
    case request
    case invite
    case founder
}

struct Membership: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    var userID: String
    var role: MembershipRole
    var status: MembershipStatus
    var source: MembershipSource
    var joinedAt: Date
    var leftAt: Date?
}

extension Membership {
    /// One membership document per (group, user) pair, id'd deterministically
    /// rather than by a random UUID — status transitions (active → left →
    /// active again on rejoin) reuse the same document instead of piling up
    /// duplicates, and it's what lets firestore.rules cheaply check "is this
    /// user a member of this group" with a single exists() rather than a query
    /// (security rules can't run arbitrary queries, only fetch a doc by path).
    static func compositeID(groupID: String, userID: String) -> String {
        "\(groupID)_\(userID)"
    }
}
