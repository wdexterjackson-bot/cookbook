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

    /// Whether `userID` has already liked this publication — drives
    /// GroupCookbookView's like button state.
    func hasLiked(_ publicationID: String, userID: String) async throws -> Bool
    /// Sets `userID`'s like state and returns the publication's new total
    /// like count. A no-op (returns the current count unchanged) if
    /// `liked` already matches the existing state — e.g. liking twice in a
    /// race doesn't double-count.
    @discardableResult
    func setLiked(_ publicationID: String, userID: String, liked: Bool) async throws -> Int
}
