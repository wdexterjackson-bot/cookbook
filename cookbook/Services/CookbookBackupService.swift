//
//  CookbookBackupService.swift
//  cookbook
//
//  Pure logic, no SwiftUI, matching RecipeSearch.swift's own "testable
//  without SwiftUI" convention. exportData reads a Cookbook + its Recipes
//  into a CookbookBackupArchive (see that file's header for the format's
//  design); restore always creates a brand-new Cookbook with fresh UUIDs
//  (cookbook, sections, recipes) rather than touching anything that
//  already exists, so it's safe to run on a device that still has the
//  original — a per-recipe photo decode/write failure is non-fatal,
//  matching the existing "photo failure doesn't block the rest" precedent
//  in RecipePhotoUploadServicing/the Family Cookbook publish flow.
//

import Foundation
import SwiftData

enum CookbookBackupError: Error, Equatable {
    /// The file's schemaVersion is newer than this build of the app
    /// understands — e.g. restoring a backup made by a future app version
    /// on an older install.
    case unsupportedSchemaVersion(Int)
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

    @discardableResult
    static func restore(_ data: Data, ownerID: String, modelContext: ModelContext) throws -> Cookbook {
        let archive = try jsonDecoder.decode(CookbookBackupArchive.self, from: data)
        guard archive.schemaVersion <= CookbookBackupArchive.currentSchemaVersion else {
            throw CookbookBackupError.unsupportedSchemaVersion(archive.schemaVersion)
        }

        let cookbook = Cookbook.restoring(from: archive.cookbook, ownerID: ownerID)
        modelContext.insert(cookbook)

        var sectionIDRemap: [UUID: UUID] = [:]
        cookbook.sections = archive.cookbook.chapters.map { chapterPayload in
            let section = CookbookSection(title: chapterPayload.title, sortOrder: chapterPayload.sortOrder)
            sectionIDRemap[chapterPayload.id] = section.id
            return section
        }

        for recipePayload in archive.cookbook.recipes {
            let remappedSectionID = recipePayload.originalSectionID.flatMap { sectionIDRemap[$0] }
            let recipe = Recipe.restoring(
                from: recipePayload,
                ownerID: ownerID,
                cookbookID: cookbook.id,
                sectionID: remappedSectionID
            )
            modelContext.insert(recipe)
        }

        try modelContext.save()
        return cookbook
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
        recipe.updatedAt = payload.updatedAt
        recipe.language = payload.language

        recipe.rootOriginRecipeID = payload.rootOriginRecipeID
        recipe.immediateSourceRecipeID = payload.immediateSourceRecipeID
        recipe.sourceOwnerSnapshot = payload.sourceOwnerSnapshot
        recipe.sourceGroupSnapshot = payload.sourceGroupSnapshot

        recipe.authorLineage = payload.authorLineage
        recipe.authorLineageIsExternal = payload.authorLineageIsExternal
        recipe.inspirationCredit = payload.inspirationCredit
        recipe.videoURLs = payload.videoURLs

        return recipe
    }
}
