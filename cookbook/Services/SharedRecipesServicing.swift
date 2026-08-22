//
//  SharedRecipesServicing.swift
//  cookbook
//
//  Friendship-gated recipe sharing (see SharedRecipe.swift). Its own
//  protocol, not folded into PublicationsServicing — there's no group,
//  cookbook, or membership involved at all, just two friends.
//

import Foundation

enum SharedRecipesServiceError: Error, Equatable {
    case notFound
    case notAuthorized
    case invalidState
    case notFriends
}

extension SharedRecipesServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound: return "That shared recipe isn't there anymore."
        case .notAuthorized: return "You don't have permission to do that."
        case .invalidState: return "That recipe has already been handled."
        case .notFriends: return "You can only share recipes with a friend."
        }
    }
}

protocol SharedRecipesServicing {
    /// `sourceRecipeID` is the sender's local Recipe.id — the same
    /// deterministic-ID reasoning as Publication: sharing the same recipe
    /// with the same friend again updates this one doc (freshly `.pending`
    /// again, even if it had been declined) rather than piling up
    /// duplicates.
    @discardableResult
    func shareRecipe(
        content: PublicationContentSnapshot,
        sourceRecipeID: String,
        from senderID: String,
        to recipientID: String
    ) async throws -> SharedRecipe

    /// Recipes shared with `userID`, most recent first.
    func fetchSharedRecipes(forRecipient userID: String) async throws -> [SharedRecipe]

    /// Recipes `userID` has shared with others, most recent first — what
    /// lets the sender see "I shared this, waiting for a response" in
    /// Messages instead of a share silently vanishing into their friend's
    /// inbox with no confirmation on their own end.
    func fetchSharedRecipes(bySender userID: String) async throws -> [SharedRecipe]

    /// Only the recipient, and only while still `.pending`.
    func markCopied(_ sharedRecipeID: String, recipientID: String) async throws
    func decline(_ sharedRecipeID: String, recipientID: String) async throws
}
