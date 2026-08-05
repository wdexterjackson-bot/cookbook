//
//  DiscoveredRecipe.swift
//  cookbook
//
//  API-shaped data, not a SwiftData @Model — same reasoning as Publication
//  (2B): this doesn't need to round-trip through SwiftData until a user
//  actually imports it into their Personal Cookbook.
//

import Foundation

enum MealSource: String, Codable {
    case spoonacular
    case theMealDB
}

struct DiscoveredNutrition: Codable, Equatable {
    var calories: Double?
    var proteinGrams: Double?
    var fatGrams: Double?
    var carbsGrams: Double?
    var sugarGrams: Double?
    var fiberGrams: Double?
    var sodiumMilligrams: Double?
}

struct DiscoveredIngredient: Codable, Equatable, Identifiable {
    var id: String { displayText }
    var displayText: String
}

struct DiscoveredRecipe: Codable, Equatable, Identifiable {
    var id: String { "\(source.rawValue)-\(externalID)" }

    var source: MealSource
    var externalID: String
    var title: String
    var imageURL: String?
    var sourceURL: String?
    var servings: Int?
    var readyInMinutes: Int?
    var summary: String?
    /// Diet labels the source already verified (e.g. Spoonacular's `diets`
    /// array) — not free-text tags the user typed.
    var dietFlags: [String]
    /// nil until fetchDetails() is called — search results are
    /// intentionally lightweight (no nutrition) to keep quota cheap.
    var nutrition: DiscoveredNutrition?
    var ingredients: [DiscoveredIngredient]
    var steps: [String]
    var attributionText: String
}
