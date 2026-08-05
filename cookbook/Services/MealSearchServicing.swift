//
//  MealSearchServicing.swift
//  cookbook
//
//  The seam for external recipe search — SpoonacularMealSearchService and
//  TheMealDBMealSearchService are the real adapters (one source each),
//  FakeMealSearchService backs tests. Each conformer speaks for exactly one
//  source, so callers know upfront (via supportsDietFiltering) whether
//  diet/allergen params will actually do anything, rather than silently
//  no-opping on a source that can't honor them (TheMealDB).
//

import Foundation

enum MealSearchError: Error, Equatable {
    case recipeNotFound
    case quotaExceeded
    case invalidResponse
}

protocol MealSearchServicing {
    var source: MealSource { get }
    var supportsDietFiltering: Bool { get }

    /// Lightweight — no nutrition. Fetch details separately once a user
    /// actually opens a result, to keep search cheap on quota.
    func search(query: String, diet: DietPreference, excludedAllergens: Set<AllergenPreference>) async throws -> [DiscoveredRecipe]
    func fetchDetails(externalID: String) async throws -> DiscoveredRecipe
    func browseRandom(count: Int) async throws -> [DiscoveredRecipe]
}
