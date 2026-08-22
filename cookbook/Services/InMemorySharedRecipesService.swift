//
//  InMemorySharedRecipesService.swift
//  cookbook
//

import Foundation

final class InMemorySharedRecipesService: SharedRecipesServicing {
    private(set) var sharedRecipes: [SharedRecipe] = []

    @discardableResult
    func shareRecipe(
        content: PublicationContentSnapshot,
        sourceRecipeID: String,
        from senderID: String,
        to recipientID: String
    ) async throws -> SharedRecipe {
        let shared = SharedRecipe(
            id: SharedRecipe.compositeID(senderID: senderID, recipientID: recipientID, sourceRecipeID: sourceRecipeID),
            senderID: senderID,
            recipientID: recipientID,
            sourceRecipeID: sourceRecipeID,
            content: content,
            sharedAt: .now,
            state: .pending
        )
        if let index = sharedRecipes.firstIndex(where: { $0.id == shared.id }) {
            sharedRecipes[index] = shared
        } else {
            sharedRecipes.append(shared)
        }
        return shared
    }

    func fetchSharedRecipes(forRecipient userID: String) async throws -> [SharedRecipe] {
        sharedRecipes
            .filter { $0.recipientID == userID }
            .sorted { $0.sharedAt > $1.sharedAt }
    }

    func fetchSharedRecipes(bySender userID: String) async throws -> [SharedRecipe] {
        sharedRecipes
            .filter { $0.senderID == userID }
            .sorted { $0.sharedAt > $1.sharedAt }
    }

    func markCopied(_ sharedRecipeID: String, recipientID: String) async throws {
        try update(sharedRecipeID, recipientID: recipientID, to: .copied)
    }

    func decline(_ sharedRecipeID: String, recipientID: String) async throws {
        try update(sharedRecipeID, recipientID: recipientID, to: .declined)
    }

    private func update(_ sharedRecipeID: String, recipientID: String, to state: SharedRecipeState) throws {
        guard let index = sharedRecipes.firstIndex(where: { $0.id == sharedRecipeID }) else {
            throw SharedRecipesServiceError.notFound
        }
        guard sharedRecipes[index].recipientID == recipientID else {
            throw SharedRecipesServiceError.notAuthorized
        }
        guard sharedRecipes[index].state == .pending else {
            throw SharedRecipesServiceError.invalidState
        }
        sharedRecipes[index].state = state
    }
}
