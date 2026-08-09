//
//  CookbookMigratorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct CookbookMigratorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func createsADefaultCookbookWhenNoneExists() throws {
        let context = try makeInMemoryContext()

        let cookbook = try CookbookMigrator.ensureDefaultCookbookExists(in: context, ownerID: "owner-1")

        #expect(cookbook.title == "Personal Cookbook")
        #expect(cookbook.ownerID == "owner-1")
    }

    @Test func isIdempotentAcrossRepeatedCalls() throws {
        let context = try makeInMemoryContext()

        let first = try CookbookMigrator.ensureDefaultCookbookExists(in: context, ownerID: "owner-1")
        let second = try CookbookMigrator.ensureDefaultCookbookExists(in: context, ownerID: "owner-1")

        #expect(first.id == second.id)
        let descriptor = FetchDescriptor<Cookbook>(predicate: #Predicate<Cookbook> { $0.ownerID == "owner-1" })
        #expect(try context.fetch(descriptor).count == 1)
    }

    @Test func backfillsRecipesWithNoCookbookID() throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: "owner-1", title: "Pre-existing Recipe")
        context.insert(recipe)
        try context.save()
        #expect(recipe.cookbookID == nil)

        let cookbook = try CookbookMigrator.ensureDefaultCookbookExists(in: context, ownerID: "owner-1")

        #expect(recipe.cookbookID == cookbook.id)
    }

    @Test func doesNotTouchRecipesAlreadyAssignedToAnotherCookbook() throws {
        let context = try makeInMemoryContext()
        let otherCookbookID = UUID()
        let recipe = Recipe(ownerID: "owner-1", title: "Already Filed")
        recipe.cookbookID = otherCookbookID
        context.insert(recipe)
        try context.save()

        _ = try CookbookMigrator.ensureDefaultCookbookExists(in: context, ownerID: "owner-1")

        #expect(recipe.cookbookID == otherCookbookID)
    }

    @Test func doesNotTouchAnotherOwnersRecipesOrCookbooks() throws {
        let context = try makeInMemoryContext()
        let otherOwnerRecipe = Recipe(ownerID: "owner-2", title: "Not Mine")
        context.insert(otherOwnerRecipe)
        try context.save()

        _ = try CookbookMigrator.ensureDefaultCookbookExists(in: context, ownerID: "owner-1")

        #expect(otherOwnerRecipe.cookbookID == nil)
    }
}
