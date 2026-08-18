//
//  RecipeComment.swift
//  cookbook
//
//  A publication's comments, gated on Publication.commentsEnabled at read
//  time — no per-comment `isHidden` field, since hiding the whole list
//  when comments are off already covers moderation-by-toggle; a real
//  owner-or-admin delete (PublicationsServicing.deleteComment) covers
//  removing one bad comment without turning comments off for everyone.
//

import Foundation

struct RecipeComment: Codable, Identifiable, Equatable {
    var id: String
    var publicationID: String
    /// Denormalized from the parent publication specifically so
    /// firestore.rules can check group membership with one cheap field
    /// read instead of a get() on the publication doc for every comment
    /// read/write.
    var groupID: String
    var authorUserID: String
    /// Snapshotted at post time, same convention as
    /// `FamilyGroup.createdByDisplayName` / `Recipe.authorLineage`.
    var authorDisplayName: String
    /// No image field — structurally impossible, not just hidden in UI.
    var text: String
    var createdAt: Date
}
