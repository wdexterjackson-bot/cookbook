//
//  PostSignInCoordinatorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct PostSignInCoordinatorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func signInMigratesGuestRecipesToTheSignedInAccount() throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(recipe)
        try context.save()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)

        PostSignInCoordinator.handle(result, modelContext: context)

        #expect(recipe.ownerID == "new-uid")
    }

    @Test func existingSignInAlsoMigratesAnyRemainingGuestRecipes() throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(recipe)
        try context.save()
        let result = AuthResult(userID: "existing-uid", isNewAccount: false)

        PostSignInCoordinator.handle(result, modelContext: context)

        #expect(recipe.ownerID == "existing-uid")
    }
}
