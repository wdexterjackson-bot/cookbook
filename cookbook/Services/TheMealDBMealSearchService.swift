//
//  TheMealDBMealSearchService.swift
//  cookbook
//
//  Free, no meaningful quota, but no nutrition/allergen/diet data (verified
//  live while planning this feature) — this source powers unlimited
//  browse/random discovery, never the diet/allergen-filtered search path.
//

import Foundation

final class TheMealDBMealSearchService: MealSearchServicing {
    let source: MealSource = .theMealDB
    let supportsDietFiltering = false

    private let session: URLSession
    private let baseURL = URL(string: "https://www.themealdb.com/api/json/v1/1")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// diet/excludedAllergens are intentionally ignored — this source can't
    /// honor them (supportsDietFiltering == false signals this to callers
    /// before they even search).
    func search(query: String, diet: DietPreference, excludedAllergens: Set<AllergenPreference>) async throws -> [DiscoveredRecipe] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("search.php"), resolvingAgainstBaseURL: false) else {
            throw MealSearchError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "s", value: query)]
        let meals = try await fetchMeals(url: components.url)
        return meals.map(Self.map)
    }

    func fetchDetails(externalID: String) async throws -> DiscoveredRecipe {
        if let cached = DiscoveredRecipeCache.cachedDetails(source: .theMealDB, externalID: externalID) {
            return cached
        }
        guard var components = URLComponents(url: baseURL.appendingPathComponent("lookup.php"), resolvingAgainstBaseURL: false) else {
            throw MealSearchError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "i", value: externalID)]
        let meals = try await fetchMeals(url: components.url)
        guard let meal = meals.first else {
            throw MealSearchError.recipeNotFound
        }
        let recipe = Self.map(meal)
        DiscoveredRecipeCache.store(recipe)
        return recipe
    }

    func browseRandom(count: Int) async throws -> [DiscoveredRecipe] {
        var seenIDs = Set<String>()
        var recipes: [DiscoveredRecipe] = []
        // TheMealDB's free tier only returns one random meal per call
        // (multi-random is a paid feature), so this loops instead.
        for _ in 0..<max(count, 0) {
            let meals = try await fetchMeals(url: baseURL.appendingPathComponent("random.php"))
            guard let meal = meals.first, !seenIDs.contains(meal.idMeal) else { continue }
            seenIDs.insert(meal.idMeal)
            recipes.append(Self.map(meal))
        }
        return recipes
    }

    private func fetchMeals(url: URL?) async throws -> [TheMealDBMeal] {
        guard let url else { throw MealSearchError.invalidResponse }
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw MealSearchError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(TheMealDBResponse.self, from: data)
        return decoded.meals ?? []
    }

    private static func map(_ meal: TheMealDBMeal) -> DiscoveredRecipe {
        let ingredients = meal.ingredientLines.map { DiscoveredIngredient(displayText: $0) }
        let steps = (meal.strInstructions ?? "")
            .split(separator: "\r\n")
            .flatMap { $0.split(separator: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return DiscoveredRecipe(
            source: .theMealDB,
            externalID: meal.idMeal,
            title: meal.strMeal,
            imageURL: meal.strMealThumb,
            sourceURL: meal.strSource,
            servings: nil,
            readyInMinutes: nil,
            summary: [meal.strCategory, meal.strArea].compactMap { $0 }.joined(separator: " · "),
            dietFlags: [],
            nutrition: nil,
            ingredients: ingredients,
            steps: steps,
            attributionText: "Recipe data from TheMealDB"
        )
    }
}

private struct TheMealDBResponse: Decodable {
    let meals: [TheMealDBMeal]?
}

private struct TheMealDBMeal: Decodable {
    let idMeal: String
    let strMeal: String
    let strCategory: String?
    let strArea: String?
    let strInstructions: String?
    let strMealThumb: String?
    let strSource: String?

    let strIngredient1: String?
    let strIngredient2: String?
    let strIngredient3: String?
    let strIngredient4: String?
    let strIngredient5: String?
    let strIngredient6: String?
    let strIngredient7: String?
    let strIngredient8: String?
    let strIngredient9: String?
    let strIngredient10: String?
    let strIngredient11: String?
    let strIngredient12: String?
    let strIngredient13: String?
    let strIngredient14: String?
    let strIngredient15: String?
    let strIngredient16: String?
    let strIngredient17: String?
    let strIngredient18: String?
    let strIngredient19: String?
    let strIngredient20: String?

    let strMeasure1: String?
    let strMeasure2: String?
    let strMeasure3: String?
    let strMeasure4: String?
    let strMeasure5: String?
    let strMeasure6: String?
    let strMeasure7: String?
    let strMeasure8: String?
    let strMeasure9: String?
    let strMeasure10: String?
    let strMeasure11: String?
    let strMeasure12: String?
    let strMeasure13: String?
    let strMeasure14: String?
    let strMeasure15: String?
    let strMeasure16: String?
    let strMeasure17: String?
    let strMeasure18: String?
    let strMeasure19: String?
    let strMeasure20: String?

    /// TheMealDB uses 20 fixed numbered fields instead of an array — this
    /// flattens them into "measure ingredient" display lines, skipping
    /// empty slots.
    var ingredientLines: [String] {
        let ingredients = [
            strIngredient1, strIngredient2, strIngredient3, strIngredient4, strIngredient5,
            strIngredient6, strIngredient7, strIngredient8, strIngredient9, strIngredient10,
            strIngredient11, strIngredient12, strIngredient13, strIngredient14, strIngredient15,
            strIngredient16, strIngredient17, strIngredient18, strIngredient19, strIngredient20,
        ]
        let measures = [
            strMeasure1, strMeasure2, strMeasure3, strMeasure4, strMeasure5,
            strMeasure6, strMeasure7, strMeasure8, strMeasure9, strMeasure10,
            strMeasure11, strMeasure12, strMeasure13, strMeasure14, strMeasure15,
            strMeasure16, strMeasure17, strMeasure18, strMeasure19, strMeasure20,
        ]

        return zip(ingredients, measures).compactMap { ingredient, measure in
            guard let ingredient, !ingredient.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let trimmedMeasure = measure?.trimmingCharacters(in: .whitespaces) ?? ""
            return trimmedMeasure.isEmpty ? ingredient : "\(trimmedMeasure) \(ingredient)"
        }
    }
}
