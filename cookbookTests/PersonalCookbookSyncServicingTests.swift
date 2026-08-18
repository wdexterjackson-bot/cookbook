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

        try await service.push(cookbookDoc, recipes: [recipeDoc], expectedRemoteUpdatedAt: nil)
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
        try await service.push(makeCookbookDoc(ownerUserID: "alice", title: "Alice's Cookbook"), recipes: [], expectedRemoteUpdatedAt: nil)
        try await service.push(makeCookbookDoc(ownerUserID: "bob", title: "Bob's Cookbook"), recipes: [], expectedRemoteUpdatedAt: nil)

        let aliceSummaries = try await service.fetchSyncedCookbooks(forUser: "alice")

        #expect(aliceSummaries.map(\.title) == ["Alice's Cookbook"])
    }

    @Test func rePushingOverwritesInPlaceRatherThanDuplicating() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        let cookbookID = UUID()
        try await service.push(makeCookbookDoc(id: cookbookID, title: "Original Title"), recipes: [], expectedRemoteUpdatedAt: nil)
        try await service.push(makeCookbookDoc(id: cookbookID, title: "Renamed Title"), recipes: [], expectedRemoteUpdatedAt: nil)

        let summaries = try await service.fetchSyncedCookbooks(forUser: "alice")

        #expect(summaries.count == 1)
        #expect(summaries.first?.title == "Renamed Title")
    }

    /// The core of the fix for the "two devices, same account, both edit
    /// the same synced cookbook" data-loss bug: a push whose
    /// expectedRemoteUpdatedAt no longer matches what's actually remote
    /// (because a *different* push already landed) must be rejected, not
    /// silently overwrite it.
    @Test func pushRejectsAStaleExpectedRemoteUpdatedAt() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        let cookbookID = UUID()
        let originalUpdatedAt = Date()
        try await service.push(makeCookbookDoc(id: cookbookID, title: "Original", updatedAt: originalUpdatedAt), recipes: [], expectedRemoteUpdatedAt: nil)

        // Device A pulled the original, then pushed a real change —
        // bumping the remote's updatedAt.
        let secondUpdatedAt = originalUpdatedAt.addingTimeInterval(60)
        try await service.push(makeCookbookDoc(id: cookbookID, title: "From Device A", updatedAt: secondUpdatedAt), recipes: [], expectedRemoteUpdatedAt: originalUpdatedAt)

        // Device B pulled back when the remote was still "Original" and
        // never pulled again — its expectation (originalUpdatedAt) is now
        // stale relative to device A's push above.
        await #expect(throws: PersonalCookbookSyncError.remoteChangedSinceLastSync) {
            try await service.push(makeCookbookDoc(id: cookbookID, title: "From Device B"), recipes: [], expectedRemoteUpdatedAt: originalUpdatedAt)
        }

        // Device A's title must survive — device B's conflicting push
        // must not have gone through.
        let (stillThere, _) = try await service.pull(cookbookID: cookbookID, ownerUserID: "alice")
        #expect(stillThere.title == "From Device A")
    }

    @Test func pushSucceedsWhenExpectedRemoteUpdatedAtMatches() async throws {
        let service = InMemoryPersonalCookbookSyncService()
        let cookbookID = UUID()
        let firstUpdatedAt = Date()
        try await service.push(makeCookbookDoc(id: cookbookID, title: "First", updatedAt: firstUpdatedAt), recipes: [], expectedRemoteUpdatedAt: nil)

        // Simulates a device that DID pull first, so it knows the correct
        // expected value.
        try await service.push(makeCookbookDoc(id: cookbookID, title: "Second"), recipes: [], expectedRemoteUpdatedAt: firstUpdatedAt)

        let (result, _) = try await service.pull(cookbookID: cookbookID, ownerUserID: "alice")
        #expect(result.title == "Second")
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
        try await syncService.push(storedDoc, recipes: [], expectedRemoteUpdatedAt: nil)

        _ = try await PersonalCookbookSyncCoordinator.pull(
            cookbookID: cookbook.id, ownerUserID: "alice",
            modelContext: context, syncService: syncService
        )

        let cookbooks = try context.fetch(FetchDescriptor<Cookbook>())
        #expect(cookbooks.count == 1)
        #expect(cookbooks.first?.title == "Updated Elsewhere")
    }

    /// End-to-end version of the same fix, through the coordinator both a
    /// real device and the earlier tests actually use — two separate
    /// local contexts (simulating two devices signed into the same
    /// account, a real scenario now that Apple TV phone-pairing sign-in
    /// exists), device A pushes, device B (never having pulled A's
    /// change) attempts to push and is rejected instead of silently
    /// erasing A's edit.
    @Test func coordinatorRejectsASecondDevicesPushWithoutPullingFirst() async throws {
        let syncService = InMemoryPersonalCookbookSyncService()
        let photoService = FakePersonalCookbookPhotoUploadService()

        let deviceAContext = try makeInMemoryContext()
        let cookbookOnA = Cookbook(ownerID: "alice", title: "Weeknight Dinners")
        deviceAContext.insert(cookbookOnA)
        try deviceAContext.save()
        try await PersonalCookbookSyncCoordinator.push(
            cookbookOnA, recipes: [], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: true
        )
        cookbookOnA.title = "Renamed on Device A"
        try await PersonalCookbookSyncCoordinator.push(
            cookbookOnA, recipes: [], ownerUserID: "alice",
            syncService: syncService, photoUploadService: photoService, isActiveProMember: true
        )

        // Device B pulled the cookbook back when it was still "Weeknight
        // Dinners" (before A's rename) and never pulled again.
        let deviceBContext = try makeInMemoryContext()
        let cookbookOnB = try await PersonalCookbookSyncCoordinator.pull(
            cookbookID: cookbookOnA.id, ownerUserID: "alice",
            modelContext: deviceBContext, syncService: syncService
        )
        // Roll B's known state back to before A's rename, simulating that
        // B pulled at an earlier point in time than the push above.
        let staleUpdatedAt = cookbookOnB.lastKnownRemoteUpdatedAt.map { $0.addingTimeInterval(-60) }
        cookbookOnB.lastKnownRemoteUpdatedAt = staleUpdatedAt
        cookbookOnB.title = "Renamed on Device B"

        await #expect(throws: PersonalCookbookSyncError.remoteChangedSinceLastSync) {
            try await PersonalCookbookSyncCoordinator.push(
                cookbookOnB, recipes: [], ownerUserID: "alice",
                syncService: syncService, photoUploadService: photoService, isActiveProMember: true
            )
        }

        let (stillRemote, _) = try await syncService.pull(cookbookID: cookbookOnA.id, ownerUserID: "alice")
        #expect(stillRemote.title == "Renamed on Device A", "device B's conflicting push must not have overwritten device A's edit")
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
