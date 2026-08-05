//
//  RecipeTextFormatterTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct RecipeTextFormatterTests {

    @Test func plainTextIncludesTitleIngredientsAndSteps() {
        let recipe = Recipe(ownerID: "test-owner", title: "Skillet Cornbread", yield: "Serves 8")

        let ingredientSection = IngredientSection(heading: "Batter", sortOrder: 0)
        ingredientSection.ingredients = [
            Ingredient(displayText: "2 cups cornmeal", name: "cornmeal", sortOrder: 0)
        ]
        recipe.ingredientSections = [ingredientSection]

        let stepSection = StepSection(sortOrder: 0)
        stepSection.steps = [Step(text: "Preheat the oven to 425°F.", sortOrder: 0)]
        recipe.stepSections = [stepSection]

        let text = RecipeTextFormatter.plainText(for: recipe)

        #expect(text.contains("Skillet Cornbread"))
        #expect(text.contains("Yield: Serves 8"))
        #expect(text.contains("Batter:"))
        #expect(text.contains("- 2 cups cornmeal"))
        #expect(text.contains("1. Preheat the oven to 425°F."))
    }

    @Test func plainTextOmitsEmptySectionsWithoutCrashing() {
        let recipe = Recipe(ownerID: "test-owner", title: "Blank Recipe")

        let text = RecipeTextFormatter.plainText(for: recipe)

        #expect(text.contains("Blank Recipe"))
        #expect(!text.contains("INGREDIENTS"))
        #expect(!text.contains("STEPS"))
    }
}
