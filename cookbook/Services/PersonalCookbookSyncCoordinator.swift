//
//  PersonalCookbookSyncCoordinator.swift
//  cookbook
//
//  Bridges local SwiftData (Cookbook/Recipe) with the Firestore-only
//  PersonalCookbookSyncServicing seam and PersonalCookbookPhotoUploadServicing
//  — same separation RecipePublishingCoordinator uses for the analogous
//  Family Cookbook publish flow (photo upload + a plain-DTO Firestore
//  write, orchestrated by a coordinator that's the only place touching
//  both). Ingredient/step reconstruction on the pull side mirrors
//  CookbookBackupService's private Recipe.restoring(from:) exactly, with
//  one deliberate difference: ids are preserved, not randomized — see
//  this feature's plan (.claude/plans/mellow-spinning-flame.md) for why
//  sync needs stable ids and backup/restore doesn't.
//

import FirebaseStorage
import Foundation
import SwiftData

enum PersonalCookbookSyncCoordinator {
    // MARK: - Push

    /// Builds the DTOs from local models (uploading any photos first) and
    /// pushes them — the "quick sync" action behind CookbookConfigurationView's
    /// Sync to Cloud toggle and CookbooksHubView's Back Up action for an
    /// already-synced cookbook.
    static func push(
        _ cookbook: Cookbook,
        recipes: [Recipe],
        ownerUserID: String,
        syncService: PersonalCookbookSyncServicing,
        photoUploadService: PersonalCookbookPhotoUploadServicing,
        isActiveProMember: Bool
    ) async throws {
        // A lapsed member's push must never upload a new/changed photo
        // (Pro-exclusive), but also must not silently blank out a photo
        // URL already synced from when they were active — fetch whatever
        // is already remote, once, up front, to fall back to instead of
        // nil. Active members skip this extra round-trip entirely, since
        // they always attempt a fresh upload regardless.
        let existingRemote = isActiveProMember ? nil : try? await syncService.pull(cookbookID: cookbook.id, ownerUserID: ownerUserID)
        let existingRecipeDocsByID = Dictionary(uniqueKeysWithValues: (existingRemote?.recipes ?? []).map { ($0.id, $0) })

        var coverImageURL: String? = existingRemote?.cookbook.coverImageURL
        if let filename = cookbook.coverImageFilename, let data = PhotoStore.data(for: filename) {
            if isActiveProMember {
                // Best-effort, matching RecipePublishingCoordinator's own
                // reasoning: a cover-photo upload hiccup shouldn't block
                // syncing the cookbook's actual content — but it's logged
                // (not just swallowed) so a persistent failure is diagnosable
                // instead of just "the photo never shows up," same lesson as
                // the credit-backfill silent-try? bug.
                do {
                    coverImageURL = try await photoUploadService.upload(
                        imageData: data, ownerUserID: ownerUserID, fileKey: "cover_\(cookbook.id.uuidString)"
                    ).absoluteString
                } catch {
                    NSLog("[PersonalCookbookSync] cover image upload failed: \(error)")
                }
            } else {
                NSLog("[PersonalCookbookSync] skipping cover image upload — not an active Pro Member")
            }
        }

        let chapterDocs = cookbook.sections.map { section in
            PersonalCookbookChapterDoc(id: section.id, title: section.title, sortOrder: section.sortOrder, iconAssetName: section.iconAssetName)
        }
        let cookbookDoc = PersonalCookbookDoc(
            id: cookbook.id,
            ownerUserID: ownerUserID,
            title: cookbook.title,
            coverColorHex: cookbook.coverColorHex,
            coverStyleImageName: cookbook.coverStyleImageName,
            coverImageURL: coverImageURL,
            sortOrder: cookbook.sortOrder,
            hasBeenConfigured: cookbook.hasBeenConfigured,
            chaptersManuallyReordered: cookbook.chaptersManuallyReordered,
            createdAt: cookbook.createdAt,
            updatedAt: .now,
            chapters: chapterDocs
        )

        var recipeDocs: [PersonalCookbookRecipeDoc] = []
        for recipe in recipes {
            let doc = try await makeRecipeDoc(
                from: recipe, cookbookID: cookbook.id, ownerUserID: ownerUserID,
                photoUploadService: photoUploadService, isActiveProMember: isActiveProMember,
                existingRemoteDoc: existingRecipeDocsByID[recipe.id]
            )
            recipeDocs.append(doc)
        }

        try await syncService.push(cookbookDoc, recipes: recipeDocs)
        cookbook.lastSyncedAt = Date()
    }

    private static func makeRecipeDoc(
        from recipe: Recipe,
        cookbookID: UUID,
        ownerUserID: String,
        photoUploadService: PersonalCookbookPhotoUploadServicing,
        isActiveProMember: Bool,
        existingRemoteDoc: PersonalCookbookRecipeDoc?
    ) async throws -> PersonalCookbookRecipeDoc {
        var heroPhotoURL: String? = existingRemoteDoc?.heroPhotoURL
        if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename) {
            if isActiveProMember {
                do {
                    heroPhotoURL = try await photoUploadService.upload(
                        imageData: data, ownerUserID: ownerUserID, fileKey: recipe.id.uuidString
                    ).absoluteString
                } catch {
                    NSLog("[PersonalCookbookSync] hero photo upload failed for recipe \(recipe.id): \(error)")
                }
            } else {
                NSLog("[PersonalCookbookSync] skipping hero photo upload for recipe \(recipe.id) — not an active Pro Member")
            }
        }
        var galleryURLs: [String] = existingRemoteDoc?.galleryPhotoURLs ?? []
        if isActiveProMember {
            galleryURLs = []
            for (index, filename) in recipe.galleryPhotoFilenames.enumerated() {
                guard let data = PhotoStore.data(for: filename) else { continue }
                do {
                    let url = try await photoUploadService.upload(
                        imageData: data, ownerUserID: ownerUserID, fileKey: "\(recipe.id.uuidString)_gallery\(index)"
                    )
                    galleryURLs.append(url.absoluteString)
                } catch {
                    NSLog("[PersonalCookbookSync] gallery photo upload failed for recipe \(recipe.id): \(error)")
                }
            }
        } else if !recipe.galleryPhotoFilenames.isEmpty {
            NSLog("[PersonalCookbookSync] skipping gallery photo upload for recipe \(recipe.id) — not an active Pro Member")
        }

        return PersonalCookbookRecipeDoc(
            id: recipe.id,
            ownerUserID: ownerUserID,
            cookbookID: cookbookID,
            sectionID: recipe.sectionID,
            title: recipe.title,
            summary: recipe.summary,
            story: recipe.story,
            heroPhotoURL: heroPhotoURL,
            galleryPhotoURLs: galleryURLs,
            yield: recipe.yield,
            prepTimeMinutes: recipe.prepTimeMinutes,
            cookTimeMinutes: recipe.cookTimeMinutes,
            totalTimeMinutes: recipe.totalTimeMinutes,
            ingredientSections: recipe.ingredientSections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(IngredientSectionBackup.init(section:)),
            stepSections: recipe.stepSections
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(StepSectionBackup.init(section:)),
            notes: recipe.notes,
            sourceType: recipe.sourceType,
            sourceURL: recipe.sourceURL,
            sourceAuthorText: recipe.sourceAuthorText,
            externalSource: recipe.externalSource,
            externalSourceID: recipe.externalSourceID,
            calories: recipe.calories,
            proteinGrams: recipe.proteinGrams,
            fatGrams: recipe.fatGrams,
            carbsGrams: recipe.carbsGrams,
            sugarGrams: recipe.sugarGrams,
            fiberGrams: recipe.fiberGrams,
            sodiumMilligrams: recipe.sodiumMilligrams,
            cuisine: recipe.cuisine,
            course: recipe.course,
            dietaryLabels: recipe.dietaryLabels,
            allergens: recipe.allergens,
            tags: recipe.tags,
            equipment: recipe.equipment,
            isFavorite: recipe.isFavorite,
            personalRating: recipe.personalRating,
            privateNotes: recipe.privateNotes,
            isArchived: recipe.isArchived,
            createdAt: recipe.createdAt,
            updatedAt: recipe.updatedAt,
            language: recipe.language,
            rootOriginRecipeID: recipe.rootOriginRecipeID,
            immediateSourceRecipeID: recipe.immediateSourceRecipeID,
            sourceOwnerSnapshot: recipe.sourceOwnerSnapshot,
            sourceGroupSnapshot: recipe.sourceGroupSnapshot,
            authorLineage: recipe.authorLineage,
            authorLineageIsExternal: recipe.authorLineageIsExternal,
            inspirationCredit: recipe.inspirationCredit,
            videoURLs: recipe.videoURLs,
            prepSummary: recipe.prepSummary
        )
    }

    // MARK: - Pull

    /// Pulls a cloud-synced cookbook down and reconstructs it locally,
    /// preserving ids. If a local Cookbook with this id already exists
    /// (a re-pull after editing on another device), its content is
    /// overwritten in place rather than creating a duplicate — callers
    /// should confirm with the user before calling this when that's the
    /// case, since it discards any un-pushed local edits.
    @discardableResult
    static func pull(
        cookbookID: UUID,
        ownerUserID: String,
        modelContext: ModelContext,
        syncService: PersonalCookbookSyncServicing
    ) async throws -> Cookbook {
        let (cookbookDoc, recipeDocs) = try await syncService.pull(cookbookID: cookbookID, ownerUserID: ownerUserID)

        let cookbook = try existingOrNewCookbook(id: cookbookDoc.id, ownerUserID: ownerUserID, title: cookbookDoc.title, coverColorHex: cookbookDoc.coverColorHex, modelContext: modelContext)
        cookbook.title = cookbookDoc.title
        cookbook.coverColorHex = cookbookDoc.coverColorHex
        cookbook.coverStyleImageName = cookbookDoc.coverStyleImageName
        cookbook.sortOrder = cookbookDoc.sortOrder
        cookbook.hasBeenConfigured = cookbookDoc.hasBeenConfigured
        cookbook.chaptersManuallyReordered = cookbookDoc.chaptersManuallyReordered
        cookbook.createdAt = cookbookDoc.createdAt
        cookbook.updatedAt = cookbookDoc.updatedAt
        cookbook.isCloudSynced = true
        cookbook.lastSyncedAt = Date()

        if let coverImageURLString = cookbookDoc.coverImageURL,
           let data = await downloadImageData(from: coverImageURLString) {
            if let existingFilename = cookbook.coverImageFilename {
                PhotoStore.delete(existingFilename)
            }
            cookbook.coverImageFilename = try? PhotoStore.save(data)
        }

        try reconcileChapters(cookbookDoc.chapters, on: cookbook, modelContext: modelContext)
        try await reconcileRecipes(recipeDocs, cookbook: cookbook, ownerUserID: ownerUserID, modelContext: modelContext)

        try modelContext.save()
        return cookbook
    }

    private static func existingOrNewCookbook(id: UUID, ownerUserID: String, title: String, coverColorHex: String, modelContext: ModelContext) throws -> Cookbook {
        let descriptor = FetchDescriptor<Cookbook>(predicate: #Predicate { $0.id == id })
        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        }
        let cookbook = Cookbook(ownerID: ownerUserID, title: title, coverColorHex: coverColorHex)
        cookbook.id = id
        modelContext.insert(cookbook)
        return cookbook
    }

    private static func reconcileChapters(_ chapterDocs: [PersonalCookbookChapterDoc], on cookbook: Cookbook, modelContext: ModelContext) throws {
        var existingSectionsByID: [UUID: CookbookSection] = [:]
        for section in cookbook.sections {
            existingSectionsByID[section.id] = section
        }
        var sections: [CookbookSection] = []
        for chapterDoc in chapterDocs {
            let section = existingSectionsByID[chapterDoc.id] ?? {
                let newSection = CookbookSection(title: chapterDoc.title, sortOrder: chapterDoc.sortOrder)
                newSection.id = chapterDoc.id
                return newSection
            }()
            section.title = chapterDoc.title
            section.sortOrder = chapterDoc.sortOrder
            section.iconAssetName = chapterDoc.iconAssetName
            sections.append(section)
        }
        let keptChapterIDs = Set(chapterDocs.map(\.id))
        for section in cookbook.sections where !keptChapterIDs.contains(section.id) {
            modelContext.delete(section)
        }
        cookbook.sections = sections
    }

    private static func reconcileRecipes(_ recipeDocs: [PersonalCookbookRecipeDoc], cookbook: Cookbook, ownerUserID: String, modelContext: ModelContext) async throws {
        let cookbookID = cookbook.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
        let existingRecipes = try modelContext.fetch(descriptor)
        var existingRecipesByID: [UUID: Recipe] = [:]
        for recipe in existingRecipes {
            existingRecipesByID[recipe.id] = recipe
        }

        for recipeDoc in recipeDocs {
            let recipe: Recipe
            if let existing = existingRecipesByID[recipeDoc.id] {
                recipe = existing
            } else {
                recipe = Recipe(ownerID: ownerUserID, title: recipeDoc.title)
                recipe.id = recipeDoc.id
                modelContext.insert(recipe)
            }
            try await apply(recipeDoc, to: recipe, cookbookID: cookbookID)
        }

        let keptRecipeIDs = Set(recipeDocs.map(\.id))
        for recipe in existingRecipes where !keptRecipeIDs.contains(recipe.id) {
            if let filename = recipe.heroPhotoFilename {
                PhotoStore.delete(filename)
            }
            for filename in recipe.galleryPhotoFilenames {
                PhotoStore.delete(filename)
            }
            modelContext.delete(recipe)
        }
    }

    private static func apply(_ doc: PersonalCookbookRecipeDoc, to recipe: Recipe, cookbookID: UUID) async throws {
        recipe.cookbookID = cookbookID
        recipe.sectionID = doc.sectionID
        recipe.title = doc.title
        recipe.summary = doc.summary
        recipe.story = doc.story

        if let heroURLString = doc.heroPhotoURL,
           let data = await downloadImageData(from: heroURLString) {
            if let existingFilename = recipe.heroPhotoFilename {
                PhotoStore.delete(existingFilename)
            }
            recipe.heroPhotoFilename = try? PhotoStore.save(data)
        }
        var galleryFilenames: [String] = []
        for urlString in doc.galleryPhotoURLs {
            guard let data = await downloadImageData(from: urlString) else { continue }
            if let filename = try? PhotoStore.save(data) {
                galleryFilenames.append(filename)
            }
        }
        recipe.galleryPhotoFilenames = galleryFilenames

        recipe.yield = doc.yield
        recipe.prepTimeMinutes = doc.prepTimeMinutes
        recipe.cookTimeMinutes = doc.cookTimeMinutes
        recipe.totalTimeMinutes = doc.totalTimeMinutes

        recipe.ingredientSections = doc.ingredientSections.map { sectionPayload in
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
        recipe.stepSections = doc.stepSections.map { sectionPayload in
            let section = StepSection(heading: sectionPayload.heading, sortOrder: sectionPayload.sortOrder)
            section.steps = sectionPayload.steps.map { stepPayload in
                Step(text: stepPayload.text, sortOrder: stepPayload.sortOrder)
            }
            return section
        }

        recipe.notes = doc.notes
        recipe.sourceType = doc.sourceType
        recipe.sourceURL = doc.sourceURL
        recipe.sourceAuthorText = doc.sourceAuthorText
        recipe.externalSource = doc.externalSource
        recipe.externalSourceID = doc.externalSourceID

        recipe.calories = doc.calories
        recipe.proteinGrams = doc.proteinGrams
        recipe.fatGrams = doc.fatGrams
        recipe.carbsGrams = doc.carbsGrams
        recipe.sugarGrams = doc.sugarGrams
        recipe.fiberGrams = doc.fiberGrams
        recipe.sodiumMilligrams = doc.sodiumMilligrams

        recipe.cuisine = doc.cuisine
        recipe.course = doc.course
        recipe.dietaryLabels = doc.dietaryLabels
        recipe.allergens = doc.allergens
        recipe.tags = doc.tags
        recipe.equipment = doc.equipment

        recipe.isFavorite = doc.isFavorite
        recipe.personalRating = doc.personalRating
        recipe.privateNotes = doc.privateNotes
        recipe.isArchived = doc.isArchived

        recipe.createdAt = doc.createdAt
        recipe.updatedAt = doc.updatedAt
        recipe.language = doc.language

        recipe.rootOriginRecipeID = doc.rootOriginRecipeID
        recipe.immediateSourceRecipeID = doc.immediateSourceRecipeID
        recipe.sourceOwnerSnapshot = doc.sourceOwnerSnapshot
        recipe.sourceGroupSnapshot = doc.sourceGroupSnapshot

        recipe.authorLineage = doc.authorLineage
        recipe.authorLineageIsExternal = doc.authorLineageIsExternal
        recipe.inspirationCredit = doc.inspirationCredit
        recipe.videoURLs = doc.videoURLs
        recipe.prepSummary = doc.prepSummary
    }

    /// storage.rules' personalCookbooks/{ownerUserID}/{fileName} read rule
    /// requires request.auth != null — a plain URLSession GET on the
    /// downloadURL string carries no Firebase credential at all (the
    /// ?token= in that URL is just an anti-enumeration secret, not an
    /// auth bypass), so it was being denied by Storage on every single
    /// pull, silently, via this call's own try?. Going through the
    /// FirebaseStorage SDK instead — reference(forURL:) on the same
    /// downloadURL string — rides the app's already-signed-in session,
    /// which the rule actually requires.
    private static func downloadImageData(from urlString: String) async -> Data? {
        do {
            return try await Storage.storage().reference(forURL: urlString).data(maxSize: 25 * 1024 * 1024)
        } catch {
            NSLog("[PersonalCookbookSync] image download failed for \(urlString): \(error)")
            return nil
        }
    }

    // MARK: - Delete

    /// Removes this cookbook's cloud footprint entirely — every photo it
    /// uploaded to Storage (cover, each recipe's hero, each gallery item —
    /// re-derived from the same deterministic fileKey scheme push() uses
    /// to upload them, since deleting doesn't need the actual bytes) plus
    /// the Firestore doc/recipes subcollection. Used by
    /// CookbookDeletionCoordinator (one cookbook) and
    /// AccountDeletionCoordinator (every cloud-synced cookbook an account
    /// owns) so neither leaves cloud photos/documents behind forever —
    /// previously nothing called this at all.
    ///
    /// Best-effort and silent on a cookbook that was never actually
    /// synced (pull() throwing .notFound here just means there's nothing
    /// to clean up) — matches the non-fatal-photo-failure precedent used
    /// throughout this file; callers don't need to check storageMode
    /// first, though CookbookDeletionCoordinator does anyway to avoid an
    /// always-doomed network round trip for a cookbook that was never
    /// cloud-synced in the first place.
    static func deleteFromCloud(
        cookbookID: UUID,
        ownerUserID: String,
        syncService: PersonalCookbookSyncServicing,
        photoUploadService: PersonalCookbookPhotoUploadServicing
    ) async {
        guard let (_, recipeDocs) = try? await syncService.pull(cookbookID: cookbookID, ownerUserID: ownerUserID) else { return }

        try? await photoUploadService.delete(ownerUserID: ownerUserID, fileKey: "cover_\(cookbookID.uuidString)")
        for recipeDoc in recipeDocs {
            try? await photoUploadService.delete(ownerUserID: ownerUserID, fileKey: recipeDoc.id.uuidString)
            for index in recipeDoc.galleryPhotoURLs.indices {
                try? await photoUploadService.delete(ownerUserID: ownerUserID, fileKey: "\(recipeDoc.id.uuidString)_gallery\(index)")
            }
        }

        do {
            try await syncService.delete(cookbookID: cookbookID, ownerUserID: ownerUserID)
        } catch {
            NSLog("[PersonalCookbookSync] cloud cookbook doc delete failed for \(cookbookID): \(error)")
        }
    }
}
