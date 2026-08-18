//
//  FriendDiscoveryServicing.swift
//  cookbook
//
//  Email-based friend discovery — deliberately server-side only, same
//  reasoning as EmailProviderLookupServicing: the real adapter calls a
//  Cloud Function (findUserByEmail, Admin SDK) so a compromised client
//  can't enumerate the userbase by hammering a client-side query.
//

import Foundation

struct DiscoveredUser: Equatable {
    var userID: String
    var displayName: String?
}

protocol FriendDiscoveryServicing {
    /// Nil for both "no such user" and "user exists but hid their email"
    /// — the caller can't distinguish the two (no enumeration signal).
    func findUser(byEmail email: String) async throws -> DiscoveredUser?
}
