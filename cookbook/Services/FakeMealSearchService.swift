//
//  FakeMealSearchService.swift
//  cookbook
//

import Foundation

final class FakeMealSearchService: MealSearchServicing {
    let source: MealSource
    let supportsDietFiltering: Bool

    var searchResults: [DiscoveredRecipe] = []
    var detailsByExternalID: [String: DiscoveredRecipe] = [:]
    var randomResults: [DiscoveredRecipe] = []

    private(set) var lastSearchDiet: DietPreference?
    private(set) var lastSearchAllergens: Set<AllergenPreference>?
    var searchCallCount = 0
    var fetchDetailsCallCount = 0

    init(source: MealSource = .spoonacular, supportsDietFiltering: Bool = true) {
        self.source = source
        self.supportsDietFiltering = supportsDietFiltering
    }

    func search(query: String, diet: DietPreference, excludedAllergens: Set<AllergenPreference>) async throws -> [DiscoveredRecipe] {
        searchCallCount += 1
        lastSearchDiet = diet
        lastSearchAllergens = excludedAllergens
        guard query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return searchResults
        }
        return searchResults.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    func fetchDetails(externalID: String) async throws -> DiscoveredRecipe {
        fetchDetailsCallCount += 1
        guard let recipe = detailsByExternalID[externalID] else {
            throw MealSearchError.recipeNotFound
        }
        return recipe
    }

    func browseRandom(count: Int) async throws -> [DiscoveredRecipe] {
        Array(randomResults.prefix(count))
    }
}
