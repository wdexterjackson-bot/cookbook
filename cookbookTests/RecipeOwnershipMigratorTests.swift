//
//  RecipeOwnershipMigratorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct RecipeOwnershipMigratorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func migratesGuestOwnedRecipesToNewOwner() throws {
        let context = try makeInMemoryContext()
        let guestRecipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(guestRecipe)
        try context.save()

        RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: context, to: "firebase-uid-123")

        #expect(guestRecipe.ownerID == "firebase-uid-123")
    }

    @Test func doesNotTouchRecipesAlreadyOwnedBySomeoneElse() throws {
        let context = try makeInMemoryContext()
        let otherRecipe = Recipe(ownerID: "already-signed-in-uid", title: "Not Mine")
        context.insert(otherRecipe)
        try context.save()

        RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: context, to: "firebase-uid-123")

        #expect(otherRecipe.ownerID == "already-signed-in-uid")
    }

    @Test func isANoOpWhenNewOwnerIsStillTheGuestIdentity() throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Still Guest")
        context.insert(recipe)
        try context.save()

        RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: context, to: LocalOwner.id)

        #expect(recipe.ownerID == LocalOwner.id)
    }
}
