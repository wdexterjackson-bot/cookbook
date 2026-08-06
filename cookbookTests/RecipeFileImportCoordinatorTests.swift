//
//  RecipeFileImportCoordinatorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct RecipeFileImportCoordinatorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    // MARK: - splitIntoRecipeChunks

    @Test func splitsMultipleRecipesOnNameLines() {
        let text = """
        Name: Cornbread
        Section: Breads

        2 cups cornmeal
        Bake at 425.

        Name: Pumpkin Pie
        Section: Desserts

        1 can pumpkin
        Bake at 350.
        """

        let chunks = RecipeFileImportCoordinator.splitIntoRecipeChunks(text)

        #expect(chunks.count == 2)
        #expect(chunks[0].hasPrefix("Name: Cornbread"))
        #expect(chunks[0].contains("2 cups cornmeal"))
        #expect(!chunks[0].contains("Pumpkin Pie"))
        #expect(chunks[1].hasPrefix("Name: Pumpkin Pie"))
    }

    @Test func discardsTextBeforeTheFirstNameLine() {
        let text = """
        A stray header line that isn't part of any recipe.

        Name: Cornbread
        2 cups cornmeal
        """

        let chunks = RecipeFileImportCoordinator.splitIntoRecipeChunks(text)

        #expect(chunks.count == 1)
        #expect(!chunks[0].contains("stray header"))
    }

    @Test func returnsNoChunksWhenThereIsNoNameLineAtAll() {
        let chunks = RecipeFileImportCoordinator.splitIntoRecipeChunks("just some text\nwith no labels")

        #expect(chunks.isEmpty)
    }

    // MARK: - importRecipes

    @Test func importsMultipleRecipesIntoTheChosenCookbook() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let text = "Name: Cornbread\nchunk one\n\nName: Pumpkin Pie\nchunk two"
        let service = FakeRecipeLineImportService()
        service.stubbedResultsByInput["Name: Cornbread\nchunk one"] = ParsedRecipeLines(
            title: "Cornbread", ingredients: [ParsedIngredientLine(name: "cornmeal", quantity: 2, unit: "cup")], steps: ["Bake."]
        )
        service.stubbedResultsByInput["Name: Pumpkin Pie\nchunk two"] = ParsedRecipeLines(
            title: "Pumpkin Pie", ingredients: [], steps: ["Bake."]
        )

        let result = await RecipeFileImportCoordinator.importRecipes(
            from: text,
            into: cookbook,
            ownerID: "alice",
            defaultAuthorLineage: "Anonymous",
            lineImportService: service,
            modelContext: context
        )

        #expect(result.importedTitles == ["Cornbread", "Pumpkin Pie"])
        #expect(result.failedChunks.isEmpty)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 2)
        #expect(recipes.allSatisfy { $0.cookbookID == cookbook.id })
    }

    @Test func matchesChapterByNameCaseInsensitively() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        let dessertsChapter = CookbookSection(title: "Desserts", sortOrder: 0)
        cookbook.sections = [dessertsChapter]
        context.insert(cookbook)
        try context.save()

        let text = "Name: Pumpkin Pie"
        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(title: "Pumpkin Pie", chapterName: "desserts", ingredients: [], steps: [])

        _ = await RecipeFileImportCoordinator.importRecipes(
            from: text, into: cookbook, ownerID: "alice", defaultAuthorLineage: nil,
            lineImportService: service, modelContext: context
        )

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.sectionID == dessertsChapter.id)
    }

    @Test func leavesRecipeUnfiledWhenChapterNameDoesNotMatchAnExistingChapter() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(title: "Pumpkin Pie", chapterName: "Nonexistent Chapter", ingredients: [], steps: [])

        _ = await RecipeFileImportCoordinator.importRecipes(
            from: "Name: Pumpkin Pie", into: cookbook, ownerID: "alice", defaultAuthorLineage: nil,
            lineImportService: service, modelContext: context
        )

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.sectionID == nil)
    }

    @Test func aChunksOwnByLineOverridesTheBatchDefaultAuthorLineage() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(
            title: "Grandma's Pie", ingredients: [], steps: [], authorLineageText: "Grandma Jackson of Memphis, TN"
        )

        _ = await RecipeFileImportCoordinator.importRecipes(
            from: "Name: Grandma's Pie", into: cookbook, ownerID: "alice", defaultAuthorLineage: "Anonymous",
            lineImportService: service, modelContext: context
        )

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.authorLineage == "Grandma Jackson of Memphis, TN")
    }

    @Test func fallsBackToTheBatchDefaultAuthorLineageWhenAChunkHasNoByLine() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(title: "Cornbread", ingredients: [], steps: [])

        _ = await RecipeFileImportCoordinator.importRecipes(
            from: "Name: Cornbread", into: cookbook, ownerID: "alice", defaultAuthorLineage: "Anonymous",
            lineImportService: service, modelContext: context
        )

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.authorLineage == "Anonymous")
    }

    @Test func oneFailingChunkDoesNotBlockTheRestOfTheBatch() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let text = "Name: Bad Recipe\nbroken\n\nName: Good Recipe\nfine"
        let service = FakeRecipeLineImportService()
        service.stubbedErrorsByInput["Name: Bad Recipe\nbroken"] = RecipeLineImportError.parsingFailed
        service.stubbedResultsByInput["Name: Good Recipe\nfine"] = ParsedRecipeLines(title: "Good Recipe", ingredients: [], steps: [])

        let result = await RecipeFileImportCoordinator.importRecipes(
            from: text, into: cookbook, ownerID: "alice", defaultAuthorLineage: nil,
            lineImportService: service, modelContext: context
        )

        #expect(result.importedTitles == ["Good Recipe"])
        #expect(result.failedChunks.count == 1)
        #expect(result.failedChunks[0].hasPrefix("Name: Bad Recipe"))
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 1)
    }
}
