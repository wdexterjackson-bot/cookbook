//
//  RecipeStoring.swift
//  cookbook
//
//  The seam: every place that reads or writes recipes goes through this
//  protocol. SwiftDataRecipeStore is the only real implementation today;
//  InMemoryRecipeStore backs tests and previews. Phase 2 can add a
//  Firestore-backed adapter as a new conformer without touching callers.
//

import Foundation

protocol RecipeStoring {
    func fetchAll() throws -> [Recipe]
    func create(_ recipe: Recipe) throws
    func delete(_ recipe: Recipe) throws
    /// Persists any in-place edits made directly to a fetched Recipe object.
    func save() throws
}
