//
//  JoinRequest.swift
//  cookbook
//

import Foundation

enum JoinRequestState: String, Codable {
    case pending
    case approved
    case denied
    case cancelled
    case expired
}

struct JoinRequest: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    var requesterID: String
    var note: String?
    var state: JoinRequestState
    var decidedByUserID: String?
    var createdAt: Date
    var decidedAt: Date?

    /// Deterministic id (same shape as `Membership.compositeID`) so a
    /// second request from the same person for the same group lands on the
    /// same document instead of creating a duplicate pending row that an
    /// admin sees twice and can never fully clear.
    static func compositeID(groupID: String, requesterID: String) -> String {
        "\(groupID)_\(requesterID)"
    }
}
