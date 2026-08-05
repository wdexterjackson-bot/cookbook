//
//  MealSearchServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct MealSearchServicingTests {

    private func makeRecipe(externalID: String = "1", title: String = "Cornbread") -> DiscoveredRecipe {
        DiscoveredRecipe(
            source: .spoonacular,
            externalID: externalID,
            title: title,
            imageURL: nil,
            sourceURL: nil,
            servings: 4,
            readyInMinutes: 30,
            summary: nil,
            dietFlags: [],
            nutrition: nil,
            ingredients: [],
            steps: [],
            attributionText: "Recipe data powered by Spoonacular"
        )
    }

    @Test func searchFiltersByTitle() async throws {
        let service = FakeMealSearchService()
        service.searchResults = [makeRecipe(title: "Cornbread"), makeRecipe(externalID: "2", title: "Pot Roast")]

        let results = try await service.search(query: "corn", diet: .none, excludedAllergens: [])

        #expect(results.map(\.title) == ["Cornbread"])
    }

    @Test func searchRecordsDietAndAllergenParameters() async throws {
        let service = FakeMealSearchService()
        service.searchResults = [makeRecipe()]

        _ = try await service.search(query: "corn", diet: .vegan, excludedAllergens: [.peanut, .shellfish])

        #expect(service.lastSearchDiet == .vegan)
        #expect(service.lastSearchAllergens == [.peanut, .shellfish])
    }

    @Test func fetchDetailsThrowsForUnknownID() async throws {
        let service = FakeMealSearchService()

        await #expect(throws: MealSearchError.recipeNotFound) {
            try await service.fetchDetails(externalID: "missing")
        }
    }

    @Test func fetchDetailsReturnsCachedRecipe() async throws {
        let service = FakeMealSearchService()
        let recipe = makeRecipe()
        service.detailsByExternalID[recipe.externalID] = recipe

        let fetched = try await service.fetchDetails(externalID: recipe.externalID)

        #expect(fetched.title == "Cornbread")
    }

    @Test func theMealDBSourceDoesNotSupportDietFiltering() {
        let service = FakeMealSearchService(source: .theMealDB, supportsDietFiltering: false)

        #expect(service.supportsDietFiltering == false)
        #expect(service.source == .theMealDB)
    }
}

struct DietaryPreferencesTests {

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "DietaryPreferencesTests-\(UUID())")!
    }

    @Test func defaultsToNoPreferenceWhenNothingStored() {
        let defaults = isolatedDefaults()

        #expect(DietaryPreferencesStore.current(in: defaults) == .default)
    }

    @Test func roundTripsThroughUserDefaults() {
        let defaults = isolatedDefaults()
        let preferences = DietaryPreferences(defaultDiet: .vegan, excludedAllergens: [.peanut, .treeNut])

        DietaryPreferencesStore.setCurrent(preferences, in: defaults)

        #expect(DietaryPreferencesStore.current(in: defaults) == preferences)
    }
}
