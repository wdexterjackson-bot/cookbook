//
//  Invitation.swift
//  cookbook
//

import Foundation

enum InvitationState: String, Codable {
    case pending
    case accepted
    case declined
    case revoked
    case expired
}

struct Invitation: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    var inviterID: String
    var inviteeIdentifier: String
    var role: MembershipRole
    var tokenHash: String
    var expiresAt: Date
    var state: InvitationState
}
