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

    @Test func newAccountMigratesRecipesAndGrantsPromoCredits() async throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(recipe)
        try context.save()
        let granter = FakeEntitlementGranter()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)

        await PostSignInCoordinator.handle(result, modelContext: context, entitlementGranter: granter)

        #expect(recipe.ownerID == "new-uid")
        #expect(granter.grantedUserIDs == ["new-uid"])
    }

    @Test func existingSignInMigratesButDoesNotGrantCredits() async throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(recipe)
        try context.save()
        let granter = FakeEntitlementGranter()
        let result = AuthResult(userID: "existing-uid", isNewAccount: false)

        await PostSignInCoordinator.handle(result, modelContext: context, entitlementGranter: granter)

        #expect(recipe.ownerID == "existing-uid")
        #expect(granter.grantedUserIDs.isEmpty)
    }
}
