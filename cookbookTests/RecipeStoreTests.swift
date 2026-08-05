//
//  RecipeStoreTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct RecipeStoreTests {

    @Test func createAddsRecipeToStore() throws {
        let store = InMemoryRecipeStore()
        let recipe = Recipe(ownerID: "test-owner", title: "Skillet Cornbread")

        try store.create(recipe)

        #expect(try store.fetchAll().map(\.id) == [recipe.id])
    }

    @Test func deleteRemovesRecipeFromStore() throws {
        let store = InMemoryRecipeStore()
        let recipe = Recipe(ownerID: "test-owner", title: "Peach Cobbler")
        try store.create(recipe)

        try store.delete(recipe)

        #expect(try store.fetchAll().isEmpty)
    }

    @Test func fetchAllSortsByMostRecentlyUpdated() throws {
        let store = InMemoryRecipeStore()
        let older = Recipe(ownerID: "test-owner", title: "Older")
        older.updatedAt = .now.addingTimeInterval(-3600)
        let newer = Recipe(ownerID: "test-owner", title: "Newer")
        newer.updatedAt = .now

        try store.create(older)
        try store.create(newer)

        #expect(try store.fetchAll().map(\.title) == ["Newer", "Older"])
    }

    @Test func favoriteToggleIsPersistedInPlaceWithoutRecreatingTheRecipe() throws {
        let store = InMemoryRecipeStore()
        let recipe = Recipe(ownerID: "test-owner", title: "Sunday Roast")
        try store.create(recipe)

        recipe.isFavorite = true
        try store.save()

        let fetched = try store.fetchAll()
        #expect(fetched.first?.isFavorite == true)
    }

    @Test func newRecipeHasNoLineageInPhase1() throws {
        let recipe = Recipe(ownerID: "test-owner", title: "Grandma's Biscuits")

        #expect(recipe.rootOriginRecipeID == nil)
        #expect(recipe.immediateSourceRecipeID == nil)
    }
}
