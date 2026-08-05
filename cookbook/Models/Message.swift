//
//  Message.swift
//  cookbook
//
//  MVP is an actionable inbox, not general chat (MSG-001): every message
//  has a type and, for actionable types, a target the recipient can
//  approve/decline/accept against via payloadReference.
//

import Foundation

enum MessageType: String, Codable {
    case recipeRequest
    case recipeReceived
    case groupInvitation
    case joinRequestForAdmin
    case requestDecision
    case roleChange
    case publicationNotice
    case systemNotice
}

enum MessageActionState: String, Codable {
    case pending
    case actioned
    case notApplicable
}

struct Message: Codable, Identifiable, Equatable {
    var id: String
    var type: MessageType
    var senderID: String
    var recipientID: String
    /// Points at whatever this message is actionable against — a
    /// groupID/joinRequestID/invitationID depending on `type`.
    var payloadReference: String
    var createdAt: Date
    var expiresAt: Date?
    var isRead: Bool
    var actionState: MessageActionState
}
