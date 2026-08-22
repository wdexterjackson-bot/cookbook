//
//  PublicProfileServicing.swift
//  cookbook
//
//  A general "what's this other user's friendly name" capability — the
//  one thing FriendsListView/GroupAdminManagementView's own doc comments
//  used to say this app deliberately didn't have (only findUserByEmail's
//  one-time, rate-limited lookup did). Kept as its own collection/service,
//  separate from UserProfileServicing's userProfiles (email, location,
//  discoverability) — those are private-to-the-owner fields Firestore
//  rules can't selectively hide field-by-field, so a friend being allowed
//  to read "the name" would otherwise mean also being able to read "the
//  email" from the same document. publicProfiles holds only displayName,
//  nothing else, so opening it up to friends/pending-request counterparts
//  can't leak anything more sensitive.
//

import Foundation

protocol PublicProfileServicing {
    func setDisplayName(_ displayName: String, userID: String) async throws

    /// Best-effort batch lookup, keyed by userID — a userID with no
    /// profile (account predates this feature, was deleted, or the rules
    /// deny it because there's no friend/request connection) is simply
    /// absent from the result rather than throwing, so callers can fall
    /// back to their own existing "Member \(id.suffix(6))" label per
    /// missing entry instead of losing the whole list to one bad id.
    func fetchDisplayNames(userIDs: [String]) async throws -> [String: String]
}
