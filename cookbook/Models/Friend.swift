//
//  Friend.swift
//  cookbook
//

import Foundation

enum FriendRequestStatus: String, Codable {
    case pending
    case accepted
    case declined
}

/// Doc ID is `{senderID}_{recipientID}` — direction-sensitive, unlike
/// `Friendship`'s sorted-pair ID. Two real correctness cases fall out of
/// that direction-sensitivity, both handled by `FriendsServicing.
/// sendFriendRequest`, not by rules or storage alone:
/// - Mutual/simultaneous requests (A→B while B→A is already pending)
///   resolve to one Friendship via a transaction, not two racing/
///   contradictory docs.
/// - Re-requesting after a decline updates this same doc back to
///   `.pending` rather than erroring on "already exists" — the reverse
///   direction (the original recipient choosing to send their own
///   request) is a different doc ID and just goes through create.
struct FriendRequest: Codable, Identifiable, Equatable {
    var id: String
    var senderID: String
    var recipientID: String
    var status: FriendRequestStatus
    var createdAt: Date
    var respondedAt: Date?
}

extension FriendRequest {
    static func compositeID(senderID: String, recipientID: String) -> String {
        "\(senderID)_\(recipientID)"
    }
}

/// Doc ID is the two userIDs sorted, joined with `_` — direction doesn't
/// matter for an established friendship, unlike the request that created
/// it.
struct Friendship: Codable, Identifiable, Equatable {
    var id: String
    var userIDs: [String]
    var becameFriendsAt: Date
}

extension Friendship {
    static func compositeID(_ userIDs: [String]) -> String {
        let sorted = userIDs.sorted()
        return "\(sorted[0])_\(sorted[1])"
    }
}
