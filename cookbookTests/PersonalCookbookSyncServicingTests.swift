//
//  PersonalCookbookSyncServicingTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct PersonalCookbookSyncServicingTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeCookbookDoc(id: UUID = UUID(), ownerUserID: String = "alice", title: String = "Weeknight Dinners", updatedAt: Date = .now) -> PersonalCookbookDoc {
        PersonalCookbookDoc(
            id: id, ownerUserID: ownerUserID, title: title,
            coverColorHex: "C25432", coverStyleImageName: nil, coverImageURL: nil,
            sortOrder: 0, hasBeenConfigured: true, chaptersManuallyReordered: false,
            createdAt: .now, updatedAt: updatedAt, chapters: []
        )
    }

    private func makeRecipeDoc(id: UUID = UUID(), cookbookID: UUID, ownerUserID: String = "alice", title: String = "Cornbread") -> PersonalCookbookRecipeDoc {
        PersonalCookbookRecipeDoc(
            id: id, ownerUserID: ownerUserID, cookbookID: cookbookID, sectionID: nil,
            title: title, summary: "", story: "",
            heroPhotoURL: nil, galleryPhotoURLs: [],
            yield: "", prepTimeMinutes: nil, cookTimeMinutes: nil, totalTimeMinutes: nil,
            ingredientSections: [], stepSections: [],
            notes: "", sourceType: .manual, sourceURL: nil, sourceAuthorText: nil,
            externalSource: nil, externalSourceID: nil,
            calories: nil, proteinGrams: nil, fatGrams: nil, carbsGrams: nil, sugarGrams: nil,
            fiberGrams: nil, sodiumMilligrams: nil,
            cuisine: nil, course: nil, dietaryLabels: [], allergens: [], tags: [], equipment: [],
            isFavorite: false, personalRating: nil, privateNotes: "", isArchived: false,
            createdAt: .now, updatedAt: .now, language: "en",
            rootOriginRecipeID: nil, immediateSourceRecipeID: nil,
            sourceOwnerSnapshot: nil, sourceGroupSnapshot: nil,
            authorLineage: nil, authorLineageIsExternal: false, inspirationCredit: nil,
            videoURLs: [], prepSummary: nil
        )
    }

    // MARK: - InMemoryPersonalCookbookSyncService

    @Test func pushThenPullRoundTripsToTheSameID() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        let cookbookID = UUID()
        let cookbookDoc = makeCookbookDoc(id: cookbookID)
        let recipeDoc = makeRecipeDoc(cookbookID: cookbookID)

        try await service.push(cookbookDoc, recipes: [recipeDoc])
        let (pulledCookbook, pulledRecipes) = try await service.pull(cookbookID: cookbookID, ownerUserID: "alice")

        #expect(pulledCookbook.id == cookbookID)
        #expect(pulledRecipes.map(\.id) == [recipeDoc.id])
    }

    @Test func pullingAnUnknownCookbookThrowsNotFound() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        await #expect(throws: PersonalCookbookSyncError.notFound) {
            try await service.pull(cookbookID: UUID(), ownerUserID: "alice")
        }
    }

    @Test func fetchSyncedCookbooksOnlyReturnsThatUsersCookbooks() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        try await service.push(makeCookbookDoc(ownerUserID: "alice", title: "Alice's Cookbook"), recipes: [])
        try await service.push(makeCookbookDoc(ownerUserID: "bob", title: "Bob's Cookbook"), recipes: [])

        let aliceSummaries = try await service.fetchSyncedCookbooks(forUser: "alice")

        #expect(aliceSummaries.map(\.title) == ["Alice's Cookbook"])
    }

    @Test func rePushingOverwritesInPlaceRatherThanDuplicating() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        let cookbookID = UUID()
        try await service.push(makeCookbookDoc(id: cookbookID, title: "Original Title"), recipes: [])
        try await service.push(makeCookbookDoc(id: cookbookID, title: "Renamed Title"), recipes: [])

        let summaries = try await service.fetchSyncedCookbooks(forUser: "alice")

        #expect(summaries.count == 1)
        #expect(summaries.first?.title == "Renamed Title")
    }

    // MARK: - PersonalCookbookSyncCoordinator (push builds docs, pull reconstructs preserving ids)

    @Test func coordinatorPushThenPullPreservesCookbookAndRecipeIDs() async throws {
        let context = try makeInMemoryContext()
        let syncService = InMemoryPersonalCookbookSyncService()
        let photoService = FakePersonalCookbookPhotoUploadService()

        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners")
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        recipe.cookbookID = cookbook.id
        context.insert(cookbook)
        context.insert(recipe)
        try context.save()

        try await PersonalCookbookSyncCoordinator.push(
            cookbook, recipes: [recipe], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: true
        )

        // Simulate a second device: fresh in-memory context, nothing local yet.
        let secondDeviceContext = try makeInMemoryContext()
        let pulled = try await PersonalCookbookSyncCoordinator.pull(
            cookbookID: cookbook.id, ownerUserID: "alice",
            modelContext: secondDeviceContext, syncService: syncService
        )

        #expect(pulled.id == cookbook.id)
        #expect(pulled.title == "Weeknight Dinners")
        #expect(pulled.isCloudSynced)

        let pulledRecipes = try secondDeviceContext.fetch(FetchDescriptor<Recipe>())
        #expect(pulledRecipes.map(\.id) == [recipe.id])
        #expect(pulledRecipes.map(\.title) == ["Cornbread"])
    }

    @Test func pushingAsANonProMemberSkipsPhotoUploadEntirely() async throws {
        let context = try makeInMemoryContext()
        let syncService = InMemoryPersonalCookbookSyncService()
        let photoService = FakePersonalCookbookPhotoUploadService()

        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners")
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        recipe.cookbookID = cookbook.id
        recipe.heroPhotoFilename = try PhotoStore.save(Data([0xFF, 0xD8, 0xFF]))
        context.insert(cookbook)
        context.insert(recipe)
        try context.save()

        try await PersonalCookbookSyncCoordinator.push(
            cookbook, recipes: [recipe], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: false
        )

        #expect(photoService.uploadedFileKeys.isEmpty)
        let (_, pulledRecipes) = try await syncService.pull(cookbookID: cookbook.id, ownerUserID: "alice")
        #expect(pulledRecipes.first?.heroPhotoURL == nil)

        PhotoStore.delete(recipe.heroPhotoFilename!)
    }

    /// The gate must not silently blank out a photo already synced from
    /// when the account was an active Pro Member — only new uploads are
    /// Pro-exclusive, not already-synced state.
    @Test func lapsingAfterAPreviousProPushPreservesTheAlreadySyncedPhotoURL() async throws {
        let context = try makeInMemoryContext()
        let syncService = InMemoryPersonalCookbookSyncService()
        let photoService = FakePersonalCookbookPhotoUploadService()

        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners")
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        recipe.cookbookID = cookbook.id
        recipe.heroPhotoFilename = try PhotoStore.save(Data([0xFF, 0xD8, 0xFF]))
        context.insert(cookbook)
        context.insert(recipe)
        try context.save()

        try await PersonalCookbookSyncCoordinator.push(
            cookbook, recipes: [recipe], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: true
        )
        let (_, firstPullRecipes) = try await syncService.pull(cookbookID: cookbook.id, ownerUserID: "alice")
        let originalURL = firstPullRecipes.first?.heroPhotoURL
        #expect(originalURL != nil)
        #expect(photoService.uploadedFileKeys.count == 1)

        // Membership lapses; re-push with no local photo change.
        try await PersonalCookbookSyncCoordinator.push(
            cookbook, recipes: [recipe], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: false
        )

        #expect(photoService.uploadedFileKeys.count == 1, "a lapsed push must not upload again")
        let (_, secondPullRecipes) = try await syncService.pull(cookbookID: cookbook.id, ownerUserID: "alice")
        #expect(secondPullRecipes.first?.heroPhotoURL == originalURL, "the previously-synced URL must survive a lapsed re-push")

        PhotoStore.delete(recipe.heroPhotoFilename!)
    }

    @Test func pullingATwiceSyncedCookbookOverwritesTheLocalCopyInPlace() async throws {
        let context = try makeInMemoryContext()
        let syncService = InMemoryPersonalCookbookSyncService()
        let photoService = FakePersonalCookbookPhotoUploadService()

        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners")
        context.insert(cookbook)
        try context.save()

        try await PersonalCookbookSyncCoordinator.push(
            cookbook, recipes: [], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: true
        )
        _ = try await PersonalCookbookSyncCoordinator.pull(
            cookbookID: cookbook.id, ownerUserID: "alice",
            modelContext: context, syncService: syncService
        )

        // Someone edits the cloud copy (simulating another device), then re-pull locally.
        var storedDoc = syncService.cookbooksByID[cookbook.id]!
        storedDoc.title = "Updated Elsewhere"
        try await syncService.push(storedDoc, recipes: [])

        _ = try await PersonalCookbookSyncCoordinator.pull(
            cookbookID: cookbook.id, ownerUserID: "alice",
            modelContext: context, syncService: syncService
        )

        let cookbooks = try context.fetch(FetchDescriptor<Cookbook>())
        #expect(cookbooks.count == 1)
        #expect(cookbooks.first?.title == "Updated Elsewhere")
    }

    @Test func pullRemovesLocalRecipesNoLongerPresentInTheCloudDoc() async throws {
        let context = try makeInMemoryContext()
        let syncService = InMemoryPersonalCookbookSyncService()
        let photoService = FakePersonalCookbookPhotoUploadService()

        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners")
        let keptRecipe = Recipe(ownerID: "alice", title: "Cornbread")
        keptRecipe.cookbookID = cookbook.id
        let removedRecipe = Recipe(ownerID: "alice", title: "Chili")
        removedRecipe.cookbookID = cookbook.id
        context.insert(cookbook)
        context.insert(keptRecipe)
        context.insert(removedRecipe)
        try context.save()

        try await PersonalCookbookSyncCoordinator.push(
            cookbook, recipes: [keptRecipe], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: true
        )
        _ = try await PersonalCookbookSyncCoordinator.pull(
            cookbookID: cookbook.id, ownerUserID: "alice",
            modelContext: context, syncService: syncService
        )

        let cookbookID = cookbook.id
        let remainingRecipes = try context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID }))
        #expect(remainingRecipes.map(\.title) == ["Cornbread"])
    }
}
