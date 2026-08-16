//
//  CookbookBackupService.swift
//  cookbook
//
//  Pure logic, no SwiftUI, matching RecipeSearch.swift's own "testable
//  without SwiftUI" convention. exportData reads a Cookbook + its Recipes
//  into a CookbookBackupArchive (see that file's header for the format's
//  design); restore always creates a brand-new Cookbook shell with a fresh
//  UUID (safe to run on a device that still has the original) — a
//  per-recipe photo decode/write failure is non-fatal, matching the
//  existing "photo failure doesn't block the rest" precedent in
//  RecipePhotoUploadServicing/the Family Cookbook publish flow.
//
//  What happens to each individual RECIPE within that shell is governed
//  by RecipeRestoreMode: .addAsNew (the original, still-default behavior)
//  always creates a fresh Recipe; .overwriteExisting instead updates a
//  matching recipe (same originalRecipeID, same owner) in place —
//  wherever it currently lives, not moved into the new shell — and only
//  falls back to creating a fresh one when there's no match. Detecting
//  whether there's anything TO overwrite before committing to a mode is
//  matchingRecipeCount(in:ownerID:modelContext:).
//

import Foundation
import SwiftData

enum CookbookBackupError: Error, Equatable {
    /// The file's schemaVersion is newer than this build of the app
    /// understands — e.g. restoring a backup made by a future app version
    /// on an older install.
    case unsupportedSchemaVersion(Int)
}

/// How CookbookBackupService.restore should handle a recipe in the backup
/// whose originalRecipeID matches a recipe the owner already has.
enum RecipeRestoreMode {
    /// Always create a brand-new Recipe with a fresh id, regardless of
    /// any match — the original behavior, and the right choice when the
    /// backup has nothing in common with what's already on the device.
    case addAsNew
    /// Update the existing matching recipe's fields in place (leaving its
    /// id, cookbookID, and sectionID untouched) instead of duplicating it;
    /// recipes in the backup with no existing match still get created
    /// fresh, filed into the newly-created cookbook shell.
    case overwriteExisting
}

/// What actually happened for each recipe in a restore — lets the caller
/// report something more useful than a single recipe count when some
/// recipes were updated in place rather than added.
struct RecipeRestoreOutcome {
    var addedCount: Int
    var overwrittenCount: Int
}

enum CookbookBackupService {
    /// Shared so exportData/restore (and CookbookBackupServiceTests, which
    /// re-encodes/decodes an archive to simulate a corrupt field) always
    /// agree on the exact date strategy.
    static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func exportData(for cookbook: Cookbook, recipes: [Recipe]) throws -> Data {
        let coverImageBase64 = cookbook.coverImageFilename
            .flatMap { PhotoStore.data(for: $0) }?
            .base64EncodedString()

        let recipePayloads = recipes.map { recipe in
            RecipeBackupPayload(
                recipe: recipe,
                heroPhotoBase64: recipe.heroPhotoFilename
                    .flatMap { PhotoStore.data(for: $0) }?
                    .base64EncodedString(),
                galleryPhotoBase64: recipe.galleryPhotoFilenames.compactMap {
                    PhotoStore.data(for: $0)?.base64EncodedString()
                },
                ingredientSections: recipe.ingredientSections
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map(IngredientSectionBackup.init(section:)),
                stepSections: recipe.stepSections
                    .sorted { $0.sortOrder < $1.sortOrder }
                    .map(StepSectionBackup.init(section:))
            )
        }

        let payload = CookbookBackupPayload(
            cookbook: cookbook,
            coverImageBase64: coverImageBase64,
            recipes: recipePayloads
        )
        let archive = CookbookBackupArchive(cookbook: payload)
        return try jsonEncoder.encode(archive)
    }

    /// How many recipes in this backup file the owner already has (by
    /// originalRecipeID) — read-only, decodes the archive but touches
    /// nothing else. The caller uses this to decide whether overwrite-vs-
    /// add-new is even a meaningful choice to offer before restoring; a
    /// backup with zero matches can just restore directly as .addAsNew.
    static func matchingRecipeCount(in data: Data, ownerID: String, modelContext: ModelContext) throws -> Int {
        let archive = try jsonDecoder.decode(CookbookBackupArchive.self, from: data)
        let originalIDs = Set(archive.cookbook.recipes.compactMap(\.originalRecipeID))
        guard !originalIDs.isEmpty else { return 0 }
        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate<Recipe> { recipe in
                recipe.ownerID == ownerID && originalIDs.contains(recipe.id)
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// cookbookID is nil only when every recipe in the backup matched an
    /// existing one and was overwritten in place (mode == .overwriteExisting,
    /// addedCount == 0) — the freshly-created shell ends up with nothing
    /// filed into it, so it's discarded rather than left behind as an
    /// empty, confusing extra cookbook. cookbookTitle is always returned
    /// (read before any such discard) so the caller can still report what
    /// was restored either way.
    @discardableResult
    static func restore(
        _ data: Data,
        ownerID: String,
        modelContext: ModelContext,
        mode: RecipeRestoreMode = .addAsNew
    ) throws -> (cookbookID: UUID?, cookbookTitle: String, outcome: RecipeRestoreOutcome) {
        let archive = try jsonDecoder.decode(CookbookBackupArchive.self, from: data)
        guard archive.schemaVersion <= CookbookBackupArchive.currentSchemaVersion else {
            throw CookbookBackupError.unsupportedSchemaVersion(archive.schemaVersion)
        }

        let cookbook = Cookbook.restoring(from: archive.cookbook, ownerID: ownerID)
        modelContext.insert(cookbook)

        var sectionIDRemap: [UUID: UUID] = [:]
        cookbook.sections = archive.cookbook.chapters.map { chapterPayload in
            let section = CookbookSection(title: chapterPayload.title, sortOrder: chapterPayload.sortOrder, iconAssetName: chapterPayload.iconAssetName)
            sectionIDRemap[chapterPayload.id] = section.id
            return section
        }

        var addedCount = 0
        var overwrittenCount = 0

        for recipePayload in archive.cookbook.recipes {
            let remappedSectionID = recipePayload.originalSectionID.flatMap { sectionIDRemap[$0] }

            if mode == .overwriteExisting, let originalRecipeID = recipePayload.originalRecipeID {
                let descriptor = FetchDescriptor<Recipe>(
                    predicate: #Predicate<Recipe> { $0.ownerID == ownerID && $0.id == originalRecipeID }
                )
                if let existing = try? modelContext.fetch(descriptor).first {
                    // Left exactly where it already lives (its own
                    // cookbookID/sectionID untouched) — overwriting
                    // updates content, it doesn't relocate the recipe.
                    existing.apply(recipePayload)
                    overwrittenCount += 1
                    continue
                }
            }

            let recipe = Recipe.restoring(
                from: recipePayload,
                ownerID: ownerID,
                cookbookID: cookbook.id,
                sectionID: remappedSectionID
            )
            modelContext.insert(recipe)
            addedCount += 1
        }

        let cookbookTitle = cookbook.title
        let outcome = RecipeRestoreOutcome(addedCount: addedCount, overwrittenCount: overwrittenCount)

        guard addedCount > 0 else {
            modelContext.delete(cookbook)
            try modelContext.save()
            return (nil, cookbookTitle, outcome)
        }

        try modelContext.save()
        return (cookbook.id, cookbookTitle, outcome)
    }
}

private extension Cookbook {
    static func restoring(from payload: CookbookBackupPayload, ownerID: String) -> Cookbook {
        let cookbook = Cookbook(ownerID: ownerID, title: payload.title, coverColorHex: payload.coverColorHex)
        cookbook.coverStyleImageName = payload.coverStyleImageName
        cookbook.hasBeenConfigured = payload.hasBeenConfigured
        cookbook.chaptersManuallyReordered = payload.chaptersManuallyReordered
        cookbook.createdAt = payload.createdAt
        if let coverImageBase64 = payload.coverImageBase64,
           let data = Data(base64Encoded: coverImageBase64) {
            cookbook.coverImageFilename = try? PhotoStore.save(data)
        }
        return cookbook
    }
}

private extension Recipe {
    /// Constructs a brand-new Recipe filed into the freshly-restored
    /// cookbook shell — the .addAsNew path, and the .overwriteExisting
    /// fallback when a payload's originalRecipeID has no local match.
    static func restoring(
        from payload: RecipeBackupPayload,
        ownerID: String,
        cookbookID: UUID,
        sectionID: UUID?
    ) -> Recipe {
        let recipe = Recipe(
            ownerID: ownerID,
            title: payload.title,
            summary: payload.summary,
            story: payload.story,
            yield: payload.yield,
            sourceType: payload.sourceType
        )
        recipe.cookbookID = cookbookID
        recipe.sectionID = sectionID
        recipe.apply(payload)
        return recipe
    }

    /// Copies every backed-up field from `payload` onto `self` — used both
    /// right after constructing a brand-new Recipe above, and directly on
    /// an already-existing Recipe when overwriting in place. Deliberately
    /// never touches id/ownerID/cookbookID/sectionID: those are either
    /// fixed at construction time (a fresh Recipe) or must stay exactly
    /// as they already are (an existing Recipe being overwritten keeps
    /// living wherever it currently does, not moved into the new shell).
    func apply(_ payload: RecipeBackupPayload) {
        title = payload.title
        summary = payload.summary
        story = payload.story
        yield = payload.yield
        sourceType = payload.sourceType

        let recipe = self
        if let heroPhotoBase64 = payload.heroPhotoBase64,
           let data = Data(base64Encoded: heroPhotoBase64) {
            recipe.heroPhotoFilename = try? PhotoStore.save(data)
        }
        recipe.galleryPhotoFilenames = payload.galleryPhotoBase64.compactMap { base64 in
            guard let data = Data(base64Encoded: base64) else { return nil }
            return try? PhotoStore.save(data)
        }

        recipe.prepTimeMinutes = payload.prepTimeMinutes
        recipe.cookTimeMinutes = payload.cookTimeMinutes
        recipe.totalTimeMinutes = payload.totalTimeMinutes

        recipe.ingredientSections = payload.ingredientSections.map { sectionPayload in
            let section = IngredientSection(heading: sectionPayload.heading, sortOrder: sectionPayload.sortOrder)
            section.ingredients = sectionPayload.ingredients.map { ingredientPayload in
                Ingredient(
                    displayText: ingredientPayload.displayText,
                    name: ingredientPayload.name,
                    quantityValue: ingredientPayload.quantityValue,
                    unit: ingredientPayload.unit,
                    preparationNote: ingredientPayload.preparationNote,
                    isOptional: ingredientPayload.isOptional,
                    sortOrder: ingredientPayload.sortOrder
                )
            }
            return section
        }
        recipe.stepSections = payload.stepSections.map { sectionPayload in
            let section = StepSection(heading: sectionPayload.heading, sortOrder: sectionPayload.sortOrder)
            section.steps = sectionPayload.steps.map { stepPayload in
                Step(text: stepPayload.text, sortOrder: stepPayload.sortOrder)
            }
            return section
        }

        recipe.notes = payload.notes
        recipe.sourceURL = payload.sourceURL
        recipe.sourceAuthorText = payload.sourceAuthorText
        recipe.externalSource = payload.externalSource
        recipe.externalSourceID = payload.externalSourceID

        recipe.calories = payload.calories
        recipe.proteinGrams = payload.proteinGrams
        recipe.fatGrams = payload.fatGrams
        recipe.carbsGrams = payload.carbsGrams
        recipe.sugarGrams = payload.sugarGrams
        recipe.fiberGrams = payload.fiberGrams
        recipe.sodiumMilligrams = payload.sodiumMilligrams

        recipe.cuisine = payload.cuisine
        recipe.course = payload.course
        recipe.dietaryLabels = payload.dietaryLabels
        recipe.allergens = payload.allergens
        recipe.tags = payload.tags
        recipe.equipment = payload.equipment

        recipe.isFavorite = payload.isFavorite
        recipe.personalRating = payload.personalRating
        recipe.privateNotes = payload.privateNotes
        recipe.isArchived = payload.isArchived

        recipe.createdAt = payload.createdAt
        // Stamped fresh rather than copied from the payload — applying a
        // backup's content (new or overwritten) is itself a change
        // happening right now, not a change that happened back when the
        // backup was taken.
        recipe.updatedAt = .now
        recipe.language = payload.language

        recipe.rootOriginRecipeID = payload.rootOriginRecipeID
        recipe.immediateSourceRecipeID = payload.immediateSourceRecipeID
        recipe.sourceOwnerSnapshot = payload.sourceOwnerSnapshot
        recipe.sourceGroupSnapshot = payload.sourceGroupSnapshot

        recipe.authorLineage = payload.authorLineage
        recipe.authorLineageIsExternal = payload.authorLineageIsExternal
        recipe.inspirationCredit = payload.inspirationCredit
        recipe.videoURLs = payload.videoURLs
        recipe.prepSummary = payload.prepSummary
    }
}
