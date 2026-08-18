//
//  PublicationsServicing.swift
//  cookbook
//

import Foundation

enum PublicationsServiceError: Error, Equatable {
    case publicationNotFound
    case commentNotFound
    case commentsDisabled
    case notAuthorized
}

extension PublicationsServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .publicationNotFound: return "That recipe isn't published here anymore."
        case .commentNotFound: return "That comment isn't there anymore."
        case .commentsDisabled: return "Comments are turned off for this recipe."
        case .notAuthorized: return "You don't have permission to do that."
        }
    }
}

protocol PublicationsServicing {
    /// Publishing the same `sourceRecipeID` to the same `groupID` *and*
    /// `cookbookID` again updates the existing Publication in place — an
    /// explicit "Publish update," never silent propagation (LIN-001) —
    /// rather than creating a duplicate. Publishing the same recipe to a
    /// *different* cookbook within the same group is a genuinely separate
    /// Publication, not an update — cookbookID is part of the identity
    /// this checks, not just an extra field along for the ride.
    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, cookbookID: String, ownerUserID: String) async throws -> Publication
    func unpublish(_ publicationID: String, actingUserID: String) async throws
    /// Admin-delete-any (or the owner deleting their own) — permanent,
    /// unlike `unpublish`, which just flips state. No delete path existed
    /// for publications before this.
    func deletePublication(_ publicationID: String, actingUserID: String) async throws
    /// The owner-only "Allow Comments?" toggle — firestore.rules' existing
    /// owner-republish branch already permits this alongside content/state
    /// changes, no rules change needed for this specifically.
    func setCommentsEnabled(_ publicationID: String, enabled: Bool, actingUserID: String) async throws
    func fetchPublications(forGroup groupID: String) async throws -> [Publication]
    func fetchPublication(id: String) async throws -> Publication?

    /// All publications `ownerUserID` owns in `groupID`, regardless of
    /// state — unlike `fetchPublications(forGroup:)`, which only returns
    /// `.published` ones (that method backs the group cookbook's visible
    /// list; this one backs account deletion, which needs to reach
    /// unpublished/hidden publications too so their attribution gets
    /// tombstoned rather than left pointing at a deleted account).
    func fetchPublications(forOwner ownerUserID: String, groupID: String) async throws -> [Publication]

    /// Every publication in `groupID`, any owner, any state — unlike
    /// `fetchPublications(forGroup:)` (published-only, backs the visible
    /// cookbook list) and `fetchPublications(forOwner:groupID:)` (one
    /// owner only). Used exclusively by AccountDeletionCoordinator, which
    /// needs to find comments the deleting user left on *other* people's
    /// publications, not just their own — there's no per-author comment
    /// query available without a Firestore collection-group index this
    /// app doesn't have, so it walks every publication in each group
    /// instead.
    func fetchAllPublications(forGroup groupID: String) async throws -> [Publication]

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

    /// Same shape/reasoning as `tombstoneOwnerAttribution`, but for a
    /// single comment rather than a publication — called once per
    /// still-attributed comment during account deletion (see
    /// AccountDeletionCoordinator), not just ones on publications the
    /// user owns. Only `authorDisplayName` changes; `authorUserID`,
    /// `text`, and everything else are left as-is, matching
    /// firestore.rules' comments/update rule, which pins every field
    /// except the display name.
    func tombstoneCommentAuthorship(_ commentID: String, publicationID: String, actingUserID: String) async throws

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

    /// Every comment on a publication, oldest first — the caller is
    /// responsible for checking `Publication.commentsEnabled` before
    /// showing them (this doesn't gate on it, mirroring how
    /// fetchPublications(forGroup:) doesn't re-check membership either;
    /// firestore.rules is the real enforcement either way).
    func fetchComments(_ publicationID: String) async throws -> [RecipeComment]
    /// Throws `.commentsDisabled` if the publication doesn't have
    /// comments turned on — checked here too, not just by
    /// firestore.rules, for a clean catchable error.
    func addComment(_ publicationID: String, authorUserID: String, authorDisplayName: String, text: String) async throws -> RecipeComment
    /// Owner-or-admin, same shape as `deletePublication`.
    func deleteComment(_ commentID: String, publicationID: String, actingUserID: String) async throws
}
