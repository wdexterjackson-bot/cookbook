//
//  SwiftDataRecipeStore.swift
//  cookbook
//

import Foundation
import SwiftData

final class SwiftDataRecipeStore: RecipeStoring {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func create(_ recipe: Recipe) throws {
        context.insert(recipe)
        try save()
    }

    func delete(_ recipe: Recipe) throws {
        context.delete(recipe)
        try save()
    }

    func save() throws {
        try context.save()
    }
}
