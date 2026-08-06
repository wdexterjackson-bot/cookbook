//
//  Publication.swift
//  cookbook
//
//  Publications carry a full content snapshot, not a reference to a local
//  Recipe — personal recipes stay in SwiftData on the owner's device only
//  (Phase 2 scope decision), so Firestore is the only place other group
//  members can actually read a published recipe's content from.
//

import Foundation

enum PublicationState: String, Codable {
    case published
    case unpublished
    case hidden
}

struct PublicationIngredient: Codable, Equatable {
    var displayText: String
    var isOptional: Bool
}

struct PublicationIngredientSection: Codable, Equatable {
    var heading: String?
    var ingredients: [PublicationIngredient]
}

struct PublicationStepSection: Codable, Equatable {
    var heading: String?
    var steps: [String]
}

struct PublicationContentSnapshot: Codable, Equatable {
    var title: String
    var summary: String
    var yield: String
    var totalTimeMinutes: Int?
    var ingredientSections: [PublicationIngredientSection]
    var stepSections: [PublicationStepSection]
    var notes: String
    var tags: [String]
    /// Firebase Storage download URL for the recipe's hero photo, if it
    /// had one and the upload succeeded. Nil is a normal, expected state
    /// (text-only recipe, or a non-fatal upload failure) — never required.
    var coverImageURL: String?

    init(
        title: String,
        summary: String,
        yield: String,
        totalTimeMinutes: Int?,
        ingredientSections: [PublicationIngredientSection],
        stepSections: [PublicationStepSection],
        notes: String,
        tags: [String],
        coverImageURL: String? = nil
    ) {
        self.title = title
        self.summary = summary
        self.yield = yield
        self.totalTimeMinutes = totalTimeMinutes
        self.ingredientSections = ingredientSections
        self.stepSections = stepSections
        self.notes = notes
        self.tags = tags
        self.coverImageURL = coverImageURL
    }
}

struct Publication: Codable, Identifiable, Equatable {
    var id: String
    var groupID: String
    var ownerUserID: String
    /// The local SwiftData Recipe.id this was published from — what makes
    /// "publish this recipe again" update the existing Publication in
    /// place (LIN-001) instead of creating a duplicate, and what a copier's
    /// immediateSourceRecipeID lineage field points back at.
    var sourceRecipeID: String
    var state: PublicationState
    var publishedAt: Date
    var updatedAt: Date
    var content: PublicationContentSnapshot
}
