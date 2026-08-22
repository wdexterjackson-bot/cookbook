//
//  FriendlyNameDirectory.swift
//  cookbook
//
//  Shared cache in front of PublicProfileServicing — every friend-facing
//  screen (Friends, Messages, Chat, Share with a Friend) needs the same
//  "look up this userID's friendly name, falling back to a short id-based
//  label if none is known yet" shape, so this exists once instead of each
//  view re-implementing its own [String: String] cache.
//

import Foundation

@Observable
final class FriendlyNameDirectory {
    private let service: PublicProfileServicing
    private(set) var namesByUserID: [String: String] = [:]

    init(service: PublicProfileServicing = FirestorePublicProfileService()) {
        self.service = service
    }

    /// Same "Member \(id.suffix(6))" shape this app used everywhere for
    /// another user's identity before this existed — the fallback for a
    /// userID with no known public profile yet (an account that predates
    /// this feature, a deleted account, or a fetch that hasn't completed
    /// or succeeded).
    func label(for userID: String) -> String {
        namesByUserID[userID] ?? "Member \(userID.suffix(6))"
    }

    /// Best-effort — a failed fetch just leaves the fallback label in
    /// place for those ids rather than surfacing as an error; nothing in
    /// this app treats a friendly name as load-bearing.
    func load(userIDs: [String]) async {
        guard !userIDs.isEmpty else { return }
        if let fetched = try? await service.fetchDisplayNames(userIDs: userIDs) {
            namesByUserID.merge(fetched) { _, new in new }
        }
    }
}
