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

    // MARK: - extractVideoURLs (VIDEOS section, pulled out before the AI ever sees the chunk)

    @Test func extractsUpToThreeVideoURLsAndRemovesTheSectionFromTheRemainingText() {
        let chunk = """
        Name: Cornbread
        Notes: Best served warm.

        VIDEOS
        https://youtube.com/watch?v=dQw4w9WgXcQ
        https://youtu.be/dQw4w9WgXcQ

        2 cups cornmeal
        """

        let (remaining, videoURLs) = RecipeFileImportCoordinator.extractVideoURLs(from: chunk)

        #expect(videoURLs == ["https://youtube.com/watch?v=dQw4w9WgXcQ", "https://youtu.be/dQw4w9WgXcQ"])
        #expect(!remaining.contains("VIDEOS"))
        #expect(!remaining.contains("youtube.com"))
        #expect(remaining.contains("2 cups cornmeal"))
        #expect(remaining.contains("Notes: Best served warm."))
    }

    @Test func stopsAtThreeVideoURLsEvenWhenMoreLinesFollow() {
        let chunk = """
        Name: Cornbread

        VIDEOS
        https://youtu.be/aaaaaaaaaaa
        https://youtu.be/bbbbbbbbbbb
        https://youtu.be/ccccccccccc
        https://youtu.be/ddddddddddd
        """

        let (_, videoURLs) = RecipeFileImportCoordinator.extractVideoURLs(from: chunk)

        #expect(videoURLs.count == 3)
        #expect(!videoURLs.contains("https://youtu.be/ddddddddddd"))
    }

    @Test func skipsALineUnderVideosThatIsNotARealYouTubeLink() {
        let chunk = """
        Name: Cornbread

        VIDEOS
        not a link
        https://youtu.be/aaaaaaaaaaa
        """

        let (_, videoURLs) = RecipeFileImportCoordinator.extractVideoURLs(from: chunk)

        #expect(videoURLs == ["https://youtu.be/aaaaaaaaaaa"])
    }

    @Test func returnsNoVideoURLsAndTheOriginalTextWhenThereIsNoVideosSection() {
        let chunk = "Name: Cornbread\n\n2 cups cornmeal"

        let (remaining, videoURLs) = RecipeFileImportCoordinator.extractVideoURLs(from: chunk)

        #expect(videoURLs.isEmpty)
        #expect(remaining == chunk)
    }

    // MARK: - parseRecipes (stage 1 — read-only)

    @Test func parsesMultipleRecipesIntoDraftsWithoutTouchingModelContext() async throws {
        let text = "Name: Cornbread\nchunk one\n\nName: Pumpkin Pie\nchunk two"
        let service = FakeRecipeLineImportService()
        service.stubbedResultsByInput["Name: Cornbread\nchunk one"] = ParsedRecipeLines(
            title: "Cornbread", ingredients: [ParsedIngredientLine(name: "cornmeal", quantity: 2, unit: "cup")], steps: ["Bake."]
        )
        service.stubbedResultsByInput["Name: Pumpkin Pie\nchunk two"] = ParsedRecipeLines(
            title: "Pumpkin Pie", ingredients: [], steps: ["Bake."]
        )

        let preview = await RecipeFileImportCoordinator.parseRecipes(
            from: text, defaultAuthorLineage: "Anonymous", lineImportService: service
        )

        #expect(preview.drafts.map(\.title) == ["Cornbread", "Pumpkin Pie"])
        #expect(preview.failedChunks.isEmpty)
    }

    @Test func aChunksOwnByLineOverridesTheBatchDefaultAuthorLineage() async throws {
        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(
            title: "Grandma's Pie", ingredients: [], steps: [], authorLineageText: "Grandma Jackson of Memphis, TN"
        )

        let preview = await RecipeFileImportCoordinator.parseRecipes(
            from: "Name: Grandma's Pie", defaultAuthorLineage: "Anonymous", lineImportService: service
        )

        #expect(preview.drafts.first?.authorLineage == "Grandma Jackson of Memphis, TN")
    }

    @Test func fallsBackToTheBatchDefaultAuthorLineageWhenAChunkHasNoByLine() async throws {
        let service = FakeRecipeLineImportService()
        service.stubbedResult = ParsedRecipeLines(title: "Cornbread", ingredients: [], steps: [])

        let preview = await RecipeFileImportCoordinator.parseRecipes(
            from: "Name: Cornbread", defaultAuthorLineage: "Anonymous", lineImportService: service
        )

        #expect(preview.drafts.first?.authorLineage == "Anonymous")
    }

    @Test func oneFailingChunkDoesNotBlockTheRestOfTheBatch() async throws {
        let text = "Name: Bad Recipe\nbroken\n\nName: Good Recipe\nfine"
        let service = FakeRecipeLineImportService()
        service.stubbedErrorsByInput["Name: Bad Recipe\nbroken"] = RecipeLineImportError.parsingFailed
        service.stubbedResultsByInput["Name: Good Recipe\nfine"] = ParsedRecipeLines(title: "Good Recipe", ingredients: [], steps: [])

        let preview = await RecipeFileImportCoordinator.parseRecipes(
            from: text, defaultAuthorLineage: nil, lineImportService: service
        )

        #expect(preview.drafts.map(\.title) == ["Good Recipe"])
        #expect(preview.failedChunks.count == 1)
        #expect(preview.failedChunks[0].hasPrefix("Name: Bad Recipe"))
    }

    // MARK: - commit (stage 2 — only runs once the user approves)

    @Test func commitSavesEveryDraftIntoTheChosenCookbook() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let drafts = [
            DraftRecipe(title: "Cornbread", chapterName: nil, notes: "", authorLineage: nil, ingredients: [], steps: ["Bake."]),
            DraftRecipe(title: "Pumpkin Pie", chapterName: nil, notes: "", authorLineage: nil, ingredients: [], steps: ["Bake."]),
        ]

        let result = RecipeFileImportCoordinator.commit(drafts, into: cookbook, ownerID: "alice", modelContext: context)

        guard case .success(let count) = result else {
            Issue.record("Expected commit to succeed")
            return
        }
        #expect(count == 2)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.count == 2)
        #expect(recipes.allSatisfy { $0.cookbookID == cookbook.id })
    }

    @Test func commitMatchesChapterByNameCaseInsensitively() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        let dessertsChapter = CookbookSection(title: "Desserts", sortOrder: 0)
        cookbook.sections = [dessertsChapter]
        context.insert(cookbook)
        try context.save()

        let draft = DraftRecipe(title: "Pumpkin Pie", chapterName: "desserts", notes: "", authorLineage: nil, ingredients: [], steps: [])
        _ = RecipeFileImportCoordinator.commit([draft], into: cookbook, ownerID: "alice", modelContext: context)

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.sectionID == dessertsChapter.id)
        #expect(cookbook.sections.count == 1)
    }

    @Test func commitCreatesAMissingChapterInsteadOfLeavingTheRecipeUnfiled() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let draft = DraftRecipe(title: "Pumpkin Pie", chapterName: "Desserts", notes: "", authorLineage: nil, ingredients: [], steps: [])
        _ = RecipeFileImportCoordinator.commit([draft], into: cookbook, ownerID: "alice", modelContext: context)

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(cookbook.sections.map(\.title) == ["Desserts"])
        #expect(recipe.sectionID == cookbook.sections.first?.id)
    }

    @Test func commitReusesOneNewChapterForMultipleDraftsInTheSameBatch() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let drafts = [
            DraftRecipe(title: "Pumpkin Pie", chapterName: "Desserts", notes: "", authorLineage: nil, ingredients: [], steps: []),
            DraftRecipe(title: "Apple Crumble", chapterName: "desserts", notes: "", authorLineage: nil, ingredients: [], steps: []),
        ]
        _ = RecipeFileImportCoordinator.commit(drafts, into: cookbook, ownerID: "alice", modelContext: context)

        #expect(cookbook.sections.count == 1)
        let recipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(recipes.allSatisfy { $0.sectionID == cookbook.sections.first?.id })
    }

    @Test func commitPopulatesAuthorLineageFromTheDraft() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let draft = DraftRecipe(
            title: "Mexican Dip", chapterName: nil, notes: "", authorLineage: "Cheryl Fox of Lithonia, GA", ingredients: [], steps: []
        )
        _ = RecipeFileImportCoordinator.commit([draft], into: cookbook, ownerID: "alice", modelContext: context)

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.authorLineage == "Cheryl Fox of Lithonia, GA")
    }

    @Test func commitPopulatesVideoURLsFromTheDraft() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Family Favorites", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        let draft = DraftRecipe(
            title: "Cornbread", chapterName: nil, notes: "", authorLineage: nil, ingredients: [], steps: [],
            videoURLs: ["https://youtu.be/aaaaaaaaaaa", "https://youtu.be/bbbbbbbbbbb"]
        )
        _ = RecipeFileImportCoordinator.commit([draft], into: cookbook, ownerID: "alice", modelContext: context)

        let recipe = try #require(try context.fetch(FetchDescriptor<Recipe>()).first)
        #expect(recipe.videoURLs == ["https://youtu.be/aaaaaaaaaaa", "https://youtu.be/bbbbbbbbbbb"])
    }
}
