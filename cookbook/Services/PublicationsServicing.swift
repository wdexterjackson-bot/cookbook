//
//  PublicationsServicing.swift
//  cookbook
//

import Foundation

enum PublicationsServiceError: Error, Equatable {
    case publicationNotFound
    case notAuthorized
}

protocol PublicationsServicing {
    /// Publishing the same `sourceRecipeID` to the same `groupID` again
    /// updates the existing Publication in place — an explicit "Publish
    /// update," never silent propagation (LIN-001) — rather than creating
    /// a duplicate.
    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, ownerUserID: String) async throws -> Publication
    func unpublish(_ publicationID: String, actingUserID: String) async throws
    func fetchPublications(forGroup groupID: String) async throws -> [Publication]
    func fetchPublication(id: String) async throws -> Publication?

    /// All publications `ownerUserID` owns in `groupID`, regardless of
    /// state — unlike `fetchPublications(forGroup:)`, which only returns
    /// `.published` ones (that method backs the group cookbook's visible
    /// list; this one backs account deletion, which needs to reach
    /// unpublished/hidden publications too so their attribution gets
    /// tombstoned rather than left pointing at a deleted account).
    func fetchPublications(forOwner ownerUserID: String, groupID: String) async throws -> [Publication]

    /// Called once per publication during account deletion (see
    /// AccountDeletionCoordinator), before the underlying auth account is
    /// actually removed — the caller's owner-authorization window is still
    /// valid at that point. Overwrites `content.authorLineage` with a
    /// non-identifying tombstone; per PRD §6.6's recommended resolution, a
    /// deleted account's identity is erased/pseudonymized but existing
    /// group publications and descendants' copies survive with a label
    /// like "Original contributor deleted" rather than an orphaned
    /// reference. `ownerUserID` itself is deliberately left as-is — it's an
    /// opaque UID, not personally identifying on its own, and rewriting it
    /// would break the `resource.data.ownerUserID ==
    /// request.resource.data.ownerUserID` invariant firestore.rules relies
    /// on for every other publication-update path.
    func tombstoneOwnerAttribution(_ publicationID: String, actingUserID: String) async throws

    /// Whether `userID` has already liked this publication — drives
    /// GroupCookbookView's like button state.
    func hasLiked(_ publicationID: String, userID: String) async throws -> Bool
    /// Sets `userID`'s like state and returns the publication's new total
    /// like count. A no-op (returns the current count unchanged) if
    /// `liked` already matches the existing state — e.g. liking twice in a
    /// race doesn't double-count.
    @discardableResult
    func setLiked(_ publicationID: String, userID: String, liked: Bool) async throws -> Int

    /// `userID`'s own 1-5 rating for this publication, if they've rated it
    /// — drives GroupCookbookView's star control.
    func myRating(_ publicationID: String, userID: String) async throws -> Int?
    /// Sets/replaces `userID`'s 1-5 rating and returns the publication's
    /// new aggregate. An upsert, never additive — replacing an existing
    /// rating adjusts the sum by the delta and leaves the count unchanged.
    @discardableResult
    func setRating(_ publicationID: String, userID: String, rating: Int) async throws -> (sum: Int, count: Int)
    /// Removes `userID`'s rating entirely, if one exists — a no-op
    /// (returns the current aggregate unchanged) if they hadn't rated it.
    @discardableResult
    func clearRating(_ publicationID: String, userID: String) async throws -> (sum: Int, count: Int)
}
