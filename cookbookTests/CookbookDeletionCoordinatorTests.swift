//
//  CookbookDeletionCoordinatorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct CookbookDeletionCoordinatorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let container = try TestModelContainer.make(schema: schema)
        return ModelContext(container)
    }

    @Test func deletingACookbookDeletesItsRecipes() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners", sortOrder: 0)
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        recipe.cookbookID = cookbook.id
        context.insert(cookbook)
        context.insert(recipe)
        try context.save()

        await CookbookDeletionCoordinator.deleteCookbookAndItsRecipes(cookbook, ownerUserID: "alice", in: context)

        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cookbook>()).isEmpty)
    }

    @Test func leavesOtherCookbooksRecipesUntouched() async throws {
        let context = try makeInMemoryContext()
        let toDelete = Cookbook(ownerID: "alice", title: "Weeknight Dinners", sortOrder: 0)
        let toKeep = Cookbook(ownerID: "alice", title: "Holiday Favorites", sortOrder: 1)
        let deletedRecipe = Recipe(ownerID: "alice", title: "Cornbread")
        deletedRecipe.cookbookID = toDelete.id
        let keptRecipe = Recipe(ownerID: "alice", title: "Pumpkin Pie")
        keptRecipe.cookbookID = toKeep.id
        context.insert(toDelete)
        context.insert(toKeep)
        context.insert(deletedRecipe)
        context.insert(keptRecipe)
        try context.save()

        await CookbookDeletionCoordinator.deleteCookbookAndItsRecipes(toDelete, ownerUserID: "alice", in: context)

        let remainingRecipes = try context.fetch(FetchDescriptor<Recipe>())
        #expect(remainingRecipes.map(\.title) == ["Pumpkin Pie"])
        let remainingCookbooks = try context.fetch(FetchDescriptor<Cookbook>())
        #expect(remainingCookbooks.map(\.title) == ["Holiday Favorites"])
    }

    @Test func worksWhenItIsTheOnlyCookbook() async throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Personal Cookbook", sortOrder: 0)
        context.insert(cookbook)
        try context.save()

        await CookbookDeletionCoordinator.deleteCookbookAndItsRecipes(cookbook, ownerUserID: "alice", in: context)

        #expect(try context.fetch(FetchDescriptor<Cookbook>()).isEmpty)
    }

    @Test func recipeCountReflectsOnlyThatCookbooksRecipes() throws {
        let context = try makeInMemoryContext()
        let cookbook = Cookbook(ownerID: "alice", title: "Weeknight Dinners", sortOrder: 0)
        let otherCookbook = Cookbook(ownerID: "alice", title: "Holiday Favorites", sortOrder: 1)
        let recipeOne = Recipe(ownerID: "alice", title: "Cornbread")
        recipeOne.cookbookID = cookbook.id
        let recipeTwo = Recipe(ownerID: "alice", title: "Chili")
        recipeTwo.cookbookID = cookbook.id
        let otherRecipe = Recipe(ownerID: "alice", title: "Pumpkin Pie")
        otherRecipe.cookbookID = otherCookbook.id
        context.insert(cookbook)
        context.insert(otherCookbook)
        context.insert(recipeOne)
        context.insert(recipeTwo)
        context.insert(otherRecipe)
        try context.save()

        #expect(CookbookDeletionCoordinator.recipeCount(for: cookbook, in: context) == 2)
        #expect(CookbookDeletionCoordinator.recipeCount(for: otherCookbook, in: context) == 1)
    }
}
