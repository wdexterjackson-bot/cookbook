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
}
