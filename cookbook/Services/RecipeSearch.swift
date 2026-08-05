//
//  RecipeSearch.swift
//  cookbook
//
//  Pure filtering/sorting logic, deliberately kept out of any View so it's
//  testable without SwiftUI (SRCH-001, 002, 004).
//

import Foundation

enum RecipeSortOption: String, CaseIterable, Identifiable {
    case relevance
    case recentlyAdded
    case alphabetical
    case rating
    case time

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relevance: return "Relevance"
        case .recentlyAdded: return "Recently Added"
        case .alphabetical: return "Alphabetical"
        case .rating: return "Rating"
        case .time: return "Total Time"
        }
    }
}

/// Single-value-per-category filters, combinable (SRCH-002). A Phase 1
/// simplification of the PRD's multi-select filter chips — one active value
/// per category rather than a set of values per category.
struct RecipeFilterCriteria: Equatable {
    var searchText: String = ""
    var course: String?
    var cuisine: String?
    var tag: String?
    var dietaryLabel: String?
    var excludedAllergen: String?
    var favoritesOnly: Bool = false
    var sort: RecipeSortOption = .recentlyAdded

    var hasActiveFilters: Bool {
        course != nil || cuisine != nil || tag != nil || dietaryLabel != nil || excludedAllergen != nil || favoritesOnly
    }

    mutating func clearFilters() {
        course = nil
        cuisine = nil
        tag = nil
        dietaryLabel = nil
        excludedAllergen = nil
        favoritesOnly = false
    }
}

enum RecipeSearch {
    static func apply(_ criteria: RecipeFilterCriteria, to recipes: [Recipe]) -> [Recipe] {
        let filtered = recipes.filter { recipe in
            matchesSearchText(recipe, criteria.searchText)
                && matches(recipe.course, criteria.course)
                && matches(recipe.cuisine, criteria.cuisine)
                && (criteria.tag == nil || recipe.tags.contains(criteria.tag!))
                && (criteria.dietaryLabel == nil || recipe.dietaryLabels.contains(criteria.dietaryLabel!))
                && (criteria.excludedAllergen == nil || !recipe.allergens.contains(criteria.excludedAllergen!))
                && (!criteria.favoritesOnly || recipe.isFavorite)
        }
        return sorted(filtered, by: criteria.sort)
    }

    private static func matches(_ value: String?, _ filter: String?) -> Bool {
        guard let filter else { return true }
        return value == filter
    }

    private static func matchesSearchText(_ recipe: Recipe, _ rawText: String) -> Bool {
        let query = rawText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }

        if recipe.title.lowercased().contains(query) { return true }
        if recipe.summary.lowercased().contains(query) { return true }
        if recipe.story.lowercased().contains(query) { return true }
        if recipe.tags.contains(where: { $0.lowercased().contains(query) }) { return true }

        for section in recipe.ingredientSections {
            let matchingIngredient = section.ingredients.contains { $0.displayText.lowercased().contains(query) }
            if matchingIngredient { return true }
        }
        for section in recipe.stepSections {
            let matchingStep = section.steps.contains { $0.text.lowercased().contains(query) }
            if matchingStep { return true }
        }
        return false
    }

    private static func sorted(_ recipes: [Recipe], by option: RecipeSortOption) -> [Recipe] {
        switch option {
        case .relevance, .recentlyAdded:
            // No relevance ranking yet in Phase 1; recency is a reasonable stand-in.
            return recipes.sorted { $0.createdAt > $1.createdAt }
        case .alphabetical:
            return recipes.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .rating:
            return recipes.sorted { ($0.personalRating ?? 0) > ($1.personalRating ?? 0) }
        case .time:
            return recipes.sorted { ($0.totalTimeMinutes ?? .max) < ($1.totalTimeMinutes ?? .max) }
        }
    }
}

struct RecipeFilterOptions {
    let courses: [String]
    let cuisines: [String]
    let tags: [String]
    let dietaryLabels: [String]
    let allergens: [String]

    init(recipes: [Recipe]) {
        courses = Self.distinctSorted(recipes.compactMap(\.course))
        cuisines = Self.distinctSorted(recipes.compactMap(\.cuisine))
        tags = Self.distinctSorted(recipes.flatMap(\.tags))
        dietaryLabels = Self.distinctSorted(recipes.flatMap(\.dietaryLabels))
        allergens = Self.distinctSorted(recipes.flatMap(\.allergens))
    }

    private static func distinctSorted(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }
}
