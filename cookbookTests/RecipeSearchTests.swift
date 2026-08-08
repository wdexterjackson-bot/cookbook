//
//  RecipeSearchTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct RecipeSearchTests {

    private func makeRecipe(
        title: String,
        course: String? = nil,
        cuisine: String? = nil,
        tags: [String] = [],
        dietaryLabels: [String] = [],
        allergens: [String] = [],
        isFavorite: Bool = false
    ) -> Recipe {
        let recipe = Recipe(ownerID: "test-owner", title: title)
        recipe.course = course
        recipe.cuisine = cuisine
        recipe.tags = tags
        recipe.dietaryLabels = dietaryLabels
        recipe.allergens = allergens
        recipe.isFavorite = isFavorite
        return recipe
    }

    @Test func searchTextMatchesTitle() {
        let cornbread = makeRecipe(title: "Skillet Cornbread")
        let cobbler = makeRecipe(title: "Peach Cobbler")

        var criteria = RecipeFilterCriteria()
        criteria.searchText = "corn"

        let results = RecipeSearch.apply(criteria, to: [cornbread, cobbler])

        #expect(results.map(\.title) == ["Skillet Cornbread"])
    }

    @Test func searchTextMatchesAuthorLineage() {
        let recipe = makeRecipe(title: "Sausage Balls")
        recipe.authorLineage = "Catherine Barrentine of Memphis, TN"
        let other = makeRecipe(title: "Peach Cobbler")
        other.authorLineage = "Someone Else of Nashville, TN"

        var criteria = RecipeFilterCriteria()
        criteria.searchText = "Catherine Barrentine"

        let results = RecipeSearch.apply(criteria, to: [recipe, other])

        #expect(results.map(\.title) == ["Sausage Balls"])
    }

    @Test func searchTextMatchesInspirationCredit() {
        let recipe = makeRecipe(title: "Ham and Cheese Twirls")
        recipe.inspirationCredit = "Catherine Barrentine of Memphis, TN"
        let other = makeRecipe(title: "Peach Cobbler")

        var criteria = RecipeFilterCriteria()
        criteria.searchText = "barrentine"

        let results = RecipeSearch.apply(criteria, to: [recipe, other])

        #expect(results.map(\.title) == ["Ham and Cheese Twirls"])
    }

    @Test func searchTextMatchesIngredientDisplayText() {
        let recipe = makeRecipe(title: "Sunday Roast")
        let section = IngredientSection()
        section.ingredients = [Ingredient(displayText: "3 lb chuck roast", name: "chuck roast")]
        recipe.ingredientSections = [section]

        var criteria = RecipeFilterCriteria()
        criteria.searchText = "chuck"

        let results = RecipeSearch.apply(criteria, to: [recipe])

        #expect(results.map(\.id) == [recipe.id])
    }

    @Test func courseFilterExcludesNonMatches() {
        let breakfast = makeRecipe(title: "Pancakes", course: "Breakfast")
        let dinner = makeRecipe(title: "Pot Roast", course: "Dinner")

        var criteria = RecipeFilterCriteria()
        criteria.course = "Dinner"

        let results = RecipeSearch.apply(criteria, to: [breakfast, dinner])

        #expect(results.map(\.title) == ["Pot Roast"])
    }

    @Test func allergenExclusionFiltersOutMatchingRecipes() {
        let withPeanuts = makeRecipe(title: "Peanut Noodles", allergens: ["Peanuts"])
        let withoutPeanuts = makeRecipe(title: "Sesame Noodles", allergens: ["Sesame"])

        var criteria = RecipeFilterCriteria()
        criteria.excludedAllergen = "Peanuts"

        let results = RecipeSearch.apply(criteria, to: [withPeanuts, withoutPeanuts])

        #expect(results.map(\.title) == ["Sesame Noodles"])
    }

    @Test func favoritesOnlyFilterKeepsOnlyFavorites() {
        let favorite = makeRecipe(title: "Grandma's Biscuits", isFavorite: true)
        let notFavorite = makeRecipe(title: "Weeknight Pasta", isFavorite: false)

        var criteria = RecipeFilterCriteria()
        criteria.favoritesOnly = true

        let results = RecipeSearch.apply(criteria, to: [favorite, notFavorite])

        #expect(results.map(\.title) == ["Grandma's Biscuits"])
    }

    @Test func filtersCombineAcrossCategories() {
        let match = makeRecipe(title: "Herb Roast Chicken", course: "Dinner", tags: ["weeknight"])
        let wrongCourse = makeRecipe(title: "Herb Pancakes", course: "Breakfast", tags: ["weeknight"])
        let wrongTag = makeRecipe(title: "Slow Roast Chicken", course: "Dinner", tags: ["holiday"])

        var criteria = RecipeFilterCriteria()
        criteria.course = "Dinner"
        criteria.tag = "weeknight"

        let results = RecipeSearch.apply(criteria, to: [match, wrongCourse, wrongTag])

        #expect(results.map(\.title) == ["Herb Roast Chicken"])
    }

    @Test func alphabeticalSortIsCaseInsensitiveAndOrdered() {
        let banana = makeRecipe(title: "banana Bread")
        let apple = makeRecipe(title: "Apple Pie")

        var criteria = RecipeFilterCriteria()
        criteria.sort = .alphabetical

        let results = RecipeSearch.apply(criteria, to: [banana, apple])

        #expect(results.map(\.title) == ["Apple Pie", "banana Bread"])
    }

    @Test func timeSortPlacesRecipesWithoutATimeLast() {
        let quick = makeRecipe(title: "Quick Salad")
        quick.totalTimeMinutes = 10
        let unspecified = makeRecipe(title: "Family Stew")
        unspecified.totalTimeMinutes = nil

        var criteria = RecipeFilterCriteria()
        criteria.sort = .time

        let results = RecipeSearch.apply(criteria, to: [unspecified, quick])

        #expect(results.map(\.title) == ["Quick Salad", "Family Stew"])
    }
}
