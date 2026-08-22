//
//  SharedRecipe.swift
//  cookbook
//
//  Friendship-gated recipe sharing — a friend-to-friend counterpart to
//  Publication, minus the group/cookbook membership entirely. Reuses
//  PublicationContentSnapshot for `content` rather than a parallel type:
//  the shape (title/summary/yield/ingredients/steps/notes/tags/lineage) is
//  identical to what a publish already snapshots, and RecipeCopyCoordinator
//  already knows how to turn one back into a local Recipe. Cover photo is
//  intentionally never carried along a share (unlike a publish) — that
//  would need its own Annual-Pro-gated Storage upload path, out of scope
//  for a plain friend-to-friend recipe share.
//

import Foundation

enum SharedRecipeState: String, Codable {
    case pending
    case copied
    case declined
}

struct SharedRecipe: Codable, Identifiable, Equatable {
    var id: String
    var senderID: String
    var recipientID: String
    /// The sender's local Recipe.id this was shared from — mirrors
    /// Publication.sourceRecipeID.
    var sourceRecipeID: String
    var content: PublicationContentSnapshot
    var sharedAt: Date
    var state: SharedRecipeState
}

extension SharedRecipe {
    /// Deterministic, not a random UUID — re-sharing the same recipe with
    /// the same friend (e.g. after they declined, or just to send an
    /// updated version) overwrites this same doc rather than piling up
    /// duplicates, same reasoning as Publication.compositeID.
    static func compositeID(senderID: String, recipientID: String, sourceRecipeID: String) -> String {
        "\(senderID)_\(recipientID)_\(sourceRecipeID)"
    }
}
