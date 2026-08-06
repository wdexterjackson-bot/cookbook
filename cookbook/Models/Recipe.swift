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

    /// Which Cookbook this recipe belongs to. Optional at the type level
    /// (SwiftData lightweight migration needs new fields to default
    /// safely) but should never be nil in practice once CookbookMigrator
    /// has run at launch — a plain scalar reference, not a @Relationship,
    /// matching how ownerID/lineage fields already reference other
    /// entities without cascade-delete coupling.
    var cookbookID: UUID?
    /// Which chapter within that Cookbook, if any — nil means unfiled.
    var sectionID: UUID?

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

    /// Which external catalog (if any) this was imported from, and its ID
    /// there — distinct from sourceURL/sourceAuthorText (display-only
    /// attribution). Structured enough to answer "already in my cookbook?"
    /// before re-spending API quota importing the same recipe twice.
    var externalSource: String?
    var externalSourceID: String?

    // Nutrition — a curated subset of what Spoonacular computes, not the
    // full ~20-nutrient breakdown. Per serving, nil for manually-created
    // recipes (Phase 1 didn't have this; imports populate it directly).
    var calories: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var carbsGrams: Double?
    var sugarGrams: Double?
    var fiberGrams: Double?
    var sodiumMilligrams: Double?

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

    /// Who entered this recipe — "FName LName of City, ST" (or "...,
    /// Country" outside the US), "FName LName" with no location on file,
    /// or "Anonymous". Stamped once at creation and never changed again,
    /// even if the author's own profile name/location changes later —
    /// unrelated to the copy-chain lineage fields above. Nil only for
    /// recipes created before this field existed.
    var authorLineage: String?

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
        self.cookbookID = nil
        self.sectionID = nil
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
        self.externalSource = nil
        self.externalSourceID = nil
        self.calories = nil
        self.proteinGrams = nil
        self.fatGrams = nil
        self.carbsGrams = nil
        self.sugarGrams = nil
        self.fiberGrams = nil
        self.sodiumMilligrams = nil
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
        self.authorLineage = nil
    }
}
