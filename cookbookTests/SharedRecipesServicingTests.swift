//
//  SharedRecipesServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct SharedRecipesServicingTests {
    private func makeContent(title: String = "Skillet Cornbread") -> PublicationContentSnapshot {
        PublicationContentSnapshot(
            title: title,
            summary: "Crispy edges.",
            yield: "8 servings",
            totalTimeMinutes: 45,
            ingredientSections: [],
            stepSections: [],
            notes: "",
            tags: []
        )
    }

    @Test func sharingARecipeMakesItFetchableByTheRecipient() async throws {
        let service = InMemorySharedRecipesService()

        let shared = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-1", from: "alice", to: "bob")

        #expect(shared.state == .pending)
        let forBob = try await service.fetchSharedRecipes(forRecipient: "bob")
        #expect(forBob.map(\.id) == [shared.id])
    }

    @Test func idIsDeterministicSoReSharingUpdatesTheSameDoc() async throws {
        let service = InMemorySharedRecipesService()
        let first = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-1", from: "alice", to: "bob")
        try await service.decline(first.id, recipientID: "bob")

        let resent = try await service.shareRecipe(content: makeContent(title: "Updated Cornbread"), sourceRecipeID: "recipe-1", from: "alice", to: "bob")

        #expect(resent.id == first.id)
        #expect(resent.state == .pending)
        let forBob = try await service.fetchSharedRecipes(forRecipient: "bob")
        #expect(forBob.count == 1)
        #expect(forBob.first?.content.title == "Updated Cornbread")
    }

    @Test func onlyTheRecipientCanMarkCopied() async throws {
        let service = InMemorySharedRecipesService()
        let shared = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-1", from: "alice", to: "bob")

        await #expect(throws: SharedRecipesServiceError.notAuthorized) {
            try await service.markCopied(shared.id, recipientID: "carol")
        }
    }

    @Test func cannotDecideAnAlreadyDecidedShare() async throws {
        let service = InMemorySharedRecipesService()
        let shared = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-1", from: "alice", to: "bob")
        try await service.decline(shared.id, recipientID: "bob")

        await #expect(throws: SharedRecipesServiceError.invalidState) {
            try await service.markCopied(shared.id, recipientID: "bob")
        }
    }

    @Test func fetchSharedRecipesOnlyReturnsThatRecipientsShares() async throws {
        let service = InMemorySharedRecipesService()
        _ = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-1", from: "alice", to: "bob")
        _ = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-2", from: "alice", to: "carol")

        let forBob = try await service.fetchSharedRecipes(forRecipient: "bob")

        #expect(forBob.map(\.sourceRecipeID) == ["recipe-1"])
    }

    @Test func fetchSharedRecipesBySenderOnlyReturnsWhatTheySent() async throws {
        let service = InMemorySharedRecipesService()
        _ = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-1", from: "alice", to: "bob")
        _ = try await service.shareRecipe(content: makeContent(), sourceRecipeID: "recipe-2", from: "carol", to: "bob")

        let byAlice = try await service.fetchSharedRecipes(bySender: "alice")

        #expect(byAlice.map(\.sourceRecipeID) == ["recipe-1"])
    }
}
