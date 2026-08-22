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
        let container = try TestModelContainer.make(schema: schema)
        return ModelContext(container)
    }

    @Test func signInMigratesGuestRecipesToTheSignedInAccount() async throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(recipe)
        try context.save()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)

        try await PostSignInCoordinator.handle(result, email: "new@example.com", modelContext: context, userProfileService: InMemoryUserProfileService())

        #expect(recipe.ownerID == "new-uid")
    }

    @Test func existingSignInAlsoMigratesAnyRemainingGuestRecipes() async throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: LocalOwner.id, title: "Guest Recipe")
        context.insert(recipe)
        try context.save()
        let result = AuthResult(userID: "existing-uid", isNewAccount: false)

        try await PostSignInCoordinator.handle(result, email: "existing@example.com", modelContext: context, userProfileService: InMemoryUserProfileService())

        #expect(recipe.ownerID == "existing-uid")
    }

    @Test func syncsTheAccountsEmailOntoItsUserProfile() async throws {
        let context = try makeInMemoryContext()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)
        let userProfiles = InMemoryUserProfileService()

        try await PostSignInCoordinator.handle(result, email: "new@example.com", modelContext: context, userProfileService: userProfiles)

        #expect(userProfiles.emailsByUserID["new-uid"] == "new@example.com")
    }

    @Test func aNilEmailIsSimplySkipped() async throws {
        let context = try makeInMemoryContext()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)
        let userProfiles = InMemoryUserProfileService()

        try await PostSignInCoordinator.handle(result, email: nil, modelContext: context, userProfileService: userProfiles)

        #expect(userProfiles.emailsByUserID["new-uid"] == nil)
    }

    @Test func syncsTheAccountsDisplayNameOntoItsPublicProfile() async throws {
        let context = try makeInMemoryContext()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)
        let publicProfiles = InMemoryPublicProfileService()

        try await PostSignInCoordinator.handle(
            result, email: "new@example.com", displayName: "Dexter Jackson", modelContext: context,
            userProfileService: InMemoryUserProfileService(), publicProfileService: publicProfiles
        )

        #expect(publicProfiles.displayNamesByUserID["new-uid"] == "Dexter Jackson")
    }

    @Test func aNilOrBlankDisplayNameIsSimplySkipped() async throws {
        let context = try makeInMemoryContext()
        let result = AuthResult(userID: "new-uid", isNewAccount: true)
        let publicProfiles = InMemoryPublicProfileService()

        try await PostSignInCoordinator.handle(
            result, email: "new@example.com", displayName: "   ", modelContext: context,
            userProfileService: InMemoryUserProfileService(), publicProfileService: publicProfiles
        )

        #expect(publicProfiles.displayNamesByUserID["new-uid"] == nil)
    }
}
