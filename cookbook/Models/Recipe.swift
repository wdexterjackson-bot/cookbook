//
//  Recipe.swift
//  cookbook
//

import Foundation
import SwiftData

enum RecipeSourceType: String, Codable {
    case manual
    case webImport
    case photoOCR
    case pdfImport
    case other
}

@Model
final class Recipe {
    var id: UUID

    /// Stable local-device identifier today; becomes a real account ID once
    /// auth exists (Phase 2). Immutable by convention — nothing in the UI
    /// offers to change it.
    var ownerID: String

    var title: String
    var summary: String
    var story: String

    /// Filenames within the app's local photo directory, not raw image data.
    var heroPhotoFilename: String?
    var galleryPhotoFilenames: [String]

    var yield: String
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var totalTimeMinutes: Int?

    @Relationship(deleteRule: .cascade, inverse: nil)
    var ingredientSections: [IngredientSection]

    @Relationship(deleteRule: .cascade, inverse: nil)
    var stepSections: [StepSection]

    var notes: String
    var sourceType: RecipeSourceType
    var sourceURL: String?
    var sourceAuthorText: String?

    var cuisine: String?
    var course: String?
    var dietaryLabels: [String]
    var allergens: [String]
    var tags: [String]
    var equipment: [String]

    var isFavorite: Bool
    var personalRating: Int?
    var privateNotes: String
    var isArchived: Bool

    var createdAt: Date
    var updatedAt: Date
    var language: String

    // Lineage — inert in Phase 1 (always nil). Present now so Phase 2's
    // copy/publish flow (PRD §6) doesn't require a breaking migration.
    var rootOriginRecipeID: UUID?
    var immediateSourceRecipeID: UUID?
    var sourceOwnerSnapshot: String?
    var sourceGroupSnapshot: String?

    init(
        ownerID: String,
        title: String,
        summary: String = "",
        story: String = "",
        yield: String = "",
        sourceType: RecipeSourceType = .manual
    ) {
        self.id = UUID()
        self.ownerID = ownerID
        self.title = title
        self.summary = summary
        self.story = story
        self.heroPhotoFilename = nil
        self.galleryPhotoFilenames = []
        self.yield = yield
        self.prepTimeMinutes = nil
        self.cookTimeMinutes = nil
        self.totalTimeMinutes = nil
        self.ingredientSections = []
        self.stepSections = []
        self.notes = ""
        self.sourceType = sourceType
        self.sourceURL = nil
        self.sourceAuthorText = nil
        self.cuisine = nil
        self.course = nil
        self.dietaryLabels = []
        self.allergens = []
        self.tags = []
        self.equipment = []
        self.isFavorite = false
        self.personalRating = nil
        self.privateNotes = ""
        self.isArchived = false
        self.createdAt = .now
        self.updatedAt = .now
        self.language = Locale.current.language.languageCode?.identifier ?? "en"
        self.rootOriginRecipeID = nil
        self.immediateSourceRecipeID = nil
        self.sourceOwnerSnapshot = nil
        self.sourceGroupSnapshot = nil
    }
}
