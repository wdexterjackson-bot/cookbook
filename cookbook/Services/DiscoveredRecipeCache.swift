//
//  DiscoveredRecipeCache.swift
//  cookbook
//
//  Load-bearing, not optional polish: Spoonacular's free tier is 50
//  points/day, so re-fetching something already seen this session (or
//  earlier today) would burn quota for nothing. Full recipe details cache
//  indefinitely — a recipe's nutrition doesn't change. Search results
//  cache for a bounded window since new recipes can appear.
//

import Foundation

enum DiscoveredRecipeCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("DiscoveredRecipes", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: Recipe details (cached indefinitely)

    private static func detailsFileURL(source: MealSource, externalID: String) -> URL {
        directory.appendingPathComponent("\(source.rawValue)-\(externalID).json")
    }

    static func cachedDetails(source: MealSource, externalID: String) -> DiscoveredRecipe? {
        let url = detailsFileURL(source: source, externalID: externalID)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DiscoveredRecipe.self, from: data)
    }

    static func store(_ recipe: DiscoveredRecipe) {
        let url = detailsFileURL(source: recipe.source, externalID: recipe.externalID)
        guard let data = try? JSONEncoder().encode(recipe) else { return }
        try? data.write(to: url)
    }

    // MARK: Search results (bounded TTL)

    private struct SearchCacheEntry: Codable {
        var recipes: [DiscoveredRecipe]
        var cachedAt: Date
    }

    private static func searchFileURL(cacheKey: String) -> URL {
        directory.appendingPathComponent("search-\(cacheKey).json")
    }

    static func cachedSearchResults(cacheKey: String, maxAge: TimeInterval = 60 * 60 * 12) -> [DiscoveredRecipe]? {
        let url = searchFileURL(cacheKey: cacheKey)
        guard let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(SearchCacheEntry.self, from: data),
              Date.now.timeIntervalSince(entry.cachedAt) < maxAge
        else {
            return nil
        }
        return entry.recipes
    }

    static func storeSearchResults(_ recipes: [DiscoveredRecipe], cacheKey: String) {
        let entry = SearchCacheEntry(recipes: recipes, cachedAt: .now)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: searchFileURL(cacheKey: cacheKey))
    }

    static func searchCacheKey(query: String, diet: DietPreference, excludedAllergens: Set<AllergenPreference>) -> String {
        let allergensKey = excludedAllergens.map(\.rawValue).sorted().joined(separator: ",")
        let raw = "\(query.lowercased())|\(diet.rawValue)|\(allergensKey)"
        return NonceGenerator.sha256(raw)
    }
}
