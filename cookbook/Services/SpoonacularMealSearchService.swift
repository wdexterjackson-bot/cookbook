//
//  SpoonacularMealSearchService.swift
//  cookbook
//
//  Plain REST/JSON over URLSession — Spoonacular has no official Swift
//  SDK, and hundreds of endpoints exist that we don't need, so a small
//  hand-written client for the two calls we actually use (complexSearch,
//  recipe information) is simpler than pulling in a generated client.
//
//  Endpoint shapes below were confirmed against the live API, not just
//  docs, while planning this feature.
//

import Foundation

final class SpoonacularMealSearchService: MealSearchServicing {
    let source: MealSource = .spoonacular
    let supportsDietFiltering = true

    private let session: URLSession
    private let baseURL = URL(string: "https://api.spoonacular.com")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(query: String, diet: DietPreference, excludedAllergens: Set<AllergenPreference>) async throws -> [DiscoveredRecipe] {
        let cacheKey = DiscoveredRecipeCache.searchCacheKey(query: query, diet: diet, excludedAllergens: excludedAllergens)
        if let cached = DiscoveredRecipeCache.cachedSearchResults(cacheKey: cacheKey) {
            return cached
        }

        var queryItems = [
            URLQueryItem(name: "apiKey", value: try Secrets.spoonacularAPIKey),
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "number", value: "20"),
        ]
        if diet != .none {
            queryItems.append(URLQueryItem(name: "diet", value: diet.rawValue))
        }
        if !excludedAllergens.isEmpty {
            queryItems.append(URLQueryItem(name: "intolerances", value: excludedAllergens.map(\.rawValue).joined(separator: ",")))
        }

        let data = try await performRequest(path: "/recipes/complexSearch", queryItems: queryItems)
        let decoded = try JSONDecoder().decode(SpoonacularSearchResponse.self, from: data)
        let recipes = decoded.results.map { result in
            DiscoveredRecipe(
                source: .spoonacular,
                externalID: String(result.id),
                title: result.title,
                imageURL: result.image,
                sourceURL: nil,
                servings: nil,
                readyInMinutes: nil,
                summary: nil,
                dietFlags: [],
                nutrition: nil,
                ingredients: [],
                steps: [],
                attributionText: "Recipe data powered by Spoonacular"
            )
        }

        DiscoveredRecipeCache.storeSearchResults(recipes, cacheKey: cacheKey)
        return recipes
    }

    func fetchDetails(externalID: String) async throws -> DiscoveredRecipe {
        if let cached = DiscoveredRecipeCache.cachedDetails(source: .spoonacular, externalID: externalID) {
            return cached
        }

        let queryItems = [
            URLQueryItem(name: "apiKey", value: try Secrets.spoonacularAPIKey),
            URLQueryItem(name: "includeNutrition", value: "true"),
        ]
        let data = try await performRequest(path: "/recipes/\(externalID)/information", queryItems: queryItems)
        let info = try JSONDecoder().decode(SpoonacularRecipeInformation.self, from: data)
        let recipe = Self.map(info)

        DiscoveredRecipeCache.store(recipe)
        return recipe
    }

    func browseRandom(count: Int) async throws -> [DiscoveredRecipe] {
        // Spoonacular's random endpoint also costs quota — free/unlimited
        // browsing is TheMealDBMealSearchService's job instead.
        []
    }

    private func performRequest(path: String, queryItems: [URLQueryItem]) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw MealSearchError.invalidResponse
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw MealSearchError.invalidResponse
        }

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MealSearchError.invalidResponse
        }
        QuotaTracker.record(from: httpResponse)

        if httpResponse.statusCode == 402 {
            throw MealSearchError.quotaExceeded
        }
        guard httpResponse.statusCode == 200 else {
            throw MealSearchError.invalidResponse
        }
        return data
    }

    private static func map(_ info: SpoonacularRecipeInformation) -> DiscoveredRecipe {
        let steps: [String]
        if let analyzed = info.analyzedInstructions?.first?.steps, !analyzed.isEmpty {
            steps = analyzed.sorted { $0.number < $1.number }.map(\.step)
        } else {
            steps = []
        }

        let nutrients = info.nutrition?.nutrients ?? []
        func amount(_ name: String) -> Double? {
            nutrients.first { $0.name == name }?.amount
        }

        let nutrition = DiscoveredNutrition(
            calories: amount("Calories"),
            proteinGrams: amount("Protein"),
            fatGrams: amount("Fat"),
            carbsGrams: amount("Carbohydrates"),
            sugarGrams: amount("Sugar"),
            fiberGrams: amount("Fiber"),
            sodiumMilligrams: amount("Sodium")
        )

        return DiscoveredRecipe(
            source: .spoonacular,
            externalID: String(info.id),
            title: info.title,
            imageURL: info.image,
            sourceURL: info.sourceUrl,
            servings: info.servings,
            readyInMinutes: info.readyInMinutes,
            summary: info.summary?.strippingHTMLTags(),
            dietFlags: info.diets ?? [],
            nutrition: nutrition,
            ingredients: (info.extendedIngredients ?? []).map { DiscoveredIngredient(displayText: $0.original) },
            steps: steps,
            attributionText: "Recipe data powered by Spoonacular"
        )
    }
}

private struct SpoonacularSearchResponse: Decodable {
    struct Result: Decodable {
        let id: Int
        let title: String
        let image: String?
    }
    let results: [Result]
}

private struct SpoonacularRecipeInformation: Decodable {
    struct Ingredient: Decodable {
        let original: String
    }
    struct InstructionGroup: Decodable {
        let steps: [Step]
    }
    struct Step: Decodable {
        let number: Int
        let step: String
    }
    struct Nutrition: Decodable {
        let nutrients: [Nutrient]
    }
    struct Nutrient: Decodable {
        let name: String
        let amount: Double
        let unit: String
    }

    let id: Int
    let title: String
    let image: String?
    let sourceUrl: String?
    let servings: Int?
    let readyInMinutes: Int?
    let summary: String?
    let diets: [String]?
    let extendedIngredients: [Ingredient]?
    let analyzedInstructions: [InstructionGroup]?
    let nutrition: Nutrition?
}

private extension String {
    func strippingHTMLTags() -> String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}
