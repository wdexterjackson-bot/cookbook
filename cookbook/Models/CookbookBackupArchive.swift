//
//  CookbookBackupArchive.swift
//  cookbook
//
//  A hand-written mirror of Cookbook/CookbookSection/Recipe/
//  IngredientSection/Ingredient/StepSection/Step, not something derived
//  automatically from the SwiftData models — a backup file's format needs
//  to stay stable and decodable across future app updates, independent of
//  whatever the live schema looks like on a given day. `schemaVersion` is
//  what would let CookbookBackupService.restore reject or special-case an
//  old file if a future format change is ever actually breaking, rather
//  than just additive.
//
//  Every payload type's mapping to/from its live model lives in exactly
//  two places — the payload's own `init(recipe:)`/`init(cookbook:)`-style
//  initializer here, and the matching `static func restoring(...)` factory
//  on the model side in CookbookBackupService — so adding a new field to
//  Recipe/Cookbook later (e.g. a videoURL) means touching exactly those
//  two spots, not scattered logic. CookbookBackupServiceTests has a
//  Mirror-based guard-rail test that fails loudly if a model gains a
//  stored property neither payload type knows about yet.
//
//  Cookbook's own id is deliberately NOT part of these payloads — restore
//  always creates a brand-new Cookbook with a fresh UUID
//  (CookbookBackupService.restore), so a restore is safe to run anytime,
//  even onto a device that still has the original cookbook.
//
//  CookbookSectionBackup.id and RecipeBackupPayload.originalRecipeID ARE
//  preserved, for two different reasons: the section id is only ever used
//  to remap which (freshly-created) chapter a recipe belongs to, never
//  reused as-is; the recipe id is a real stable identifier — restore's
//  caller can look a recipe up by it later (e.g. to offer "overwrite the
//  recipe I already have" instead of always creating a duplicate).
//

import Foundation

struct CookbookBackupArchive: Codable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var exportedAt: Date
    var cookbook: CookbookBackupPayload

    init(cookbook: CookbookBackupPayload, exportedAt: Date = .now) {
        self.schemaVersion = Self.currentSchemaVersion
        self.exportedAt = exportedAt
        self.cookbook = cookbook
    }
}

struct CookbookBackupPayload: Codable {
    var title: String
    var coverColorHex: String
    var coverStyleImageName: String?
    var coverImageBase64: String?
    var hasBeenConfigured: Bool
    var chaptersManuallyReordered: Bool
    var createdAt: Date
    var chapters: [CookbookSectionBackup]
    var recipes: [RecipeBackupPayload]

    init(cookbook: Cookbook, coverImageBase64: String?, recipes: [RecipeBackupPayload]) {
        title = cookbook.title
        coverColorHex = cookbook.coverColorHex
        coverStyleImageName = cookbook.coverStyleImageName
        self.coverImageBase64 = coverImageBase64
        hasBeenConfigured = cookbook.hasBeenConfigured
        chaptersManuallyReordered = cookbook.chaptersManuallyReordered
        createdAt = cookbook.createdAt
        chapters = cookbook.sections.map(CookbookSectionBackup.init(section:))
        self.recipes = recipes
    }
}

struct CookbookSectionBackup: Codable {
    /// Preserved from the original CookbookSection — see the file header
    /// for why this id (unlike Cookbook's/Recipe's) is kept as-is.
    var id: UUID
    var title: String
    var sortOrder: Int
    var iconAssetName: String?

    init(section: CookbookSection) {
        id = section.id
        title = section.title
        sortOrder = section.sortOrder
        iconAssetName = section.iconAssetName
    }
}

struct RecipeBackupPayload: Codable {
    /// The recipe's own id at the time of backup — stable across repeated
    /// backups of the same recipe, unlike everything else here. Lets
    /// CookbookBackupService.restore recognize "this is a recipe I
    /// already have" and update it in place instead of always creating a
    /// duplicate, when the caller asks for that (RecipeRestoreMode).
    /// Optional only so a backup file made before this field existed still
    /// decodes — always populated on export from here on, and a nil value
    /// on restore is simply never treated as a match for overwriting.
    var originalRecipeID: UUID?

    /// The CookbookSectionBackup.id this recipe belonged to, if any — not
    /// a live reference, remapped to the restored section's fresh id by
    /// CookbookBackupService.restore.
    var originalSectionID: UUID?

    var title: String
    var summary: String
    var story: String

    var heroPhotoBase64: String?
    var galleryPhotoBase64: [String]

    var yield: String
    var prepTimeMinutes: Int?
    var cookTimeMinutes: Int?
    var totalTimeMinutes: Int?

    var ingredientSections: [IngredientSectionBackup]
    var stepSections: [StepSectionBackup]

    var notes: String
    var sourceType: RecipeSourceType
    var sourceURL: String?
    var sourceAuthorText: String?

    var externalSource: String?
    var externalSourceID: String?

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

    var rootOriginRecipeID: UUID?
    var immediateSourceRecipeID: UUID?
    var sourceOwnerSnapshot: String?
    var sourceGroupSnapshot: String?

    var authorLineage: String?
    var authorLineageIsExternal: Bool
    var inspirationCredit: String?
    var videoURLs: [String]
    var prepSummary: String?

    init(
        recipe: Recipe,
        heroPhotoBase64: String?,
        galleryPhotoBase64: [String],
        ingredientSections: [IngredientSectionBackup],
        stepSections: [StepSectionBackup]
    ) {
        originalRecipeID = recipe.id
        originalSectionID = recipe.sectionID
        title = recipe.title
        summary = recipe.summary
        story = recipe.story
        self.heroPhotoBase64 = heroPhotoBase64
        self.galleryPhotoBase64 = galleryPhotoBase64
        yield = recipe.yield
        prepTimeMinutes = recipe.prepTimeMinutes
        cookTimeMinutes = recipe.cookTimeMinutes
        totalTimeMinutes = recipe.totalTimeMinutes
        self.ingredientSections = ingredientSections
        self.stepSections = stepSections
        notes = recipe.notes
        sourceType = recipe.sourceType
        sourceURL = recipe.sourceURL
        sourceAuthorText = recipe.sourceAuthorText
        externalSource = recipe.externalSource
        externalSourceID = recipe.externalSourceID
        calories = recipe.calories
        proteinGrams = recipe.proteinGrams
        fatGrams = recipe.fatGrams
        carbsGrams = recipe.carbsGrams
        sugarGrams = recipe.sugarGrams
        fiberGrams = recipe.fiberGrams
        sodiumMilligrams = recipe.sodiumMilligrams
        cuisine = recipe.cuisine
        course = recipe.course
        dietaryLabels = recipe.dietaryLabels
        allergens = recipe.allergens
        tags = recipe.tags
        equipment = recipe.equipment
        isFavorite = recipe.isFavorite
        personalRating = recipe.personalRating
        privateNotes = recipe.privateNotes
        isArchived = recipe.isArchived
        createdAt = recipe.createdAt
        updatedAt = recipe.updatedAt
        language = recipe.language
        rootOriginRecipeID = recipe.rootOriginRecipeID
        immediateSourceRecipeID = recipe.immediateSourceRecipeID
        sourceOwnerSnapshot = recipe.sourceOwnerSnapshot
        sourceGroupSnapshot = recipe.sourceGroupSnapshot
        authorLineage = recipe.authorLineage
        authorLineageIsExternal = recipe.authorLineageIsExternal
        inspirationCredit = recipe.inspirationCredit
        videoURLs = recipe.videoURLs
        prepSummary = recipe.prepSummary
    }
}

struct IngredientSectionBackup: Codable {
    var heading: String?
    var sortOrder: Int
    var ingredients: [IngredientBackup]

    init(section: IngredientSection) {
        heading = section.heading
        sortOrder = section.sortOrder
        ingredients = section.ingredients.map(IngredientBackup.init(ingredient:))
    }
}

struct IngredientBackup: Codable {
    var displayText: String
    var quantityValue: Double?
    var unit: String?
    var name: String
    var preparationNote: String?
    var isOptional: Bool
    var sortOrder: Int

    init(ingredient: Ingredient) {
        displayText = ingredient.displayText
        quantityValue = ingredient.quantityValue
        unit = ingredient.unit
        name = ingredient.name
        preparationNote = ingredient.preparationNote
        isOptional = ingredient.isOptional
        sortOrder = ingredient.sortOrder
    }
}

struct StepSectionBackup: Codable {
    var heading: String?
    var sortOrder: Int
    var steps: [StepBackup]

    init(section: StepSection) {
        heading = section.heading
        sortOrder = section.sortOrder
        steps = section.steps.map(StepBackup.init(step:))
    }
}

struct StepBackup: Codable {
    var text: String
    var sortOrder: Int

    init(step: Step) {
        text = step.text
        sortOrder = step.sortOrder
    }
}
