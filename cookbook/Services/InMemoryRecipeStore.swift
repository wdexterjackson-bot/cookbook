//
//  InMemoryRecipeStore.swift
//  cookbook
//
//  Fake conformer of RecipeStoring for unit tests and SwiftUI previews.
//  No real network or disk I/O, no mocking framework required.
//

import Foundation

final class InMemoryRecipeStore: RecipeStoring {
    private(set) var recipes: [Recipe] = []

    func fetchAll() throws -> [Recipe] {
        recipes.sorted { $0.updatedAt > $1.updatedAt }
    }

    func create(_ recipe: Recipe) throws {
        recipes.append(recipe)
    }

    func delete(_ recipe: Recipe) throws {
        recipes.removeAll { $0.id == recipe.id }
    }

    func save() throws {
        // No separate persistence step for an in-memory store.
    }
}
