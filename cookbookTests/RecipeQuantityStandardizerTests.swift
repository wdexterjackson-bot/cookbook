//
//  RecipeQuantityStandardizerTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct RecipeQuantityStandardizerTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let container = try TestModelContainer.make(schema: schema)
        return ModelContext(container)
    }

    private func makeCookbook(in context: ModelContext) -> Cookbook {
        let cookbook = Cookbook(ownerID: "owner-1", title: "Test Cookbook")
        context.insert(cookbook)
        return cookbook
    }

    private func makeRecipe(in cookbook: Cookbook, context: ModelContext) -> Recipe {
        let recipe = Recipe(ownerID: "owner-1", title: "Test Recipe")
        recipe.cookbookID = cookbook.id
        context.insert(recipe)
        return recipe
    }

    @Test func rewritesDecimalDisplayTextAndQuantityValue() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "1.5 cups flour", name: "flour", quantityValue: 1.5, unit: "cups")
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        let changed = RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(changed == 1)
        #expect(ingredient.displayText == "1 1/2 cups Flour")
        #expect(ingredient.quantityValue == 1.5)
    }

    @Test func recoversFractionThatOldDecimalFieldCouldNotStore() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        // Simulates the old decimal-only text field: the author typed
        // "1/2" but the hidden quantityValue never parsed it.
        let ingredient = Ingredient(displayText: "1/2 tsp salt", name: "salt", quantityValue: nil, unit: "tsp")
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        let changed = RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(changed == 1)
        #expect(ingredient.displayText == "1/2 tsp Salt")
        #expect(ingredient.quantityValue == 0.5)
    }

    @Test func preservesTrailingAuthorNotesWhenRewritingDisplayText() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "2.33 cups flour, sifted", name: "flour", quantityValue: 2.33)
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(ingredient.displayText == "2 1/3 cups Flour, sifted")
    }

    @Test func titleCasesIngredientNameAndSectionHeading() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection(heading: "dry ingredients")
        let ingredient = Ingredient(displayText: "1 tbsp extra-virgin olive oil", name: "extra-virgin olive oil", quantityValue: 1)
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(section.heading == "Dry Ingredients")
        #expect(ingredient.name == "Extra-Virgin Olive Oil")
        #expect(ingredient.displayText == "1 tbsp Extra-Virgin Olive Oil")
    }

    @Test func leavesIngredientsWithNoLeadingQuantityUntouchedExceptCasing() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "salt, to taste", name: "salt")
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        let changed = RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(changed == 1)
        #expect(ingredient.name == "Salt")
        #expect(ingredient.displayText == "Salt, to taste")
        #expect(ingredient.quantityValue == nil)
    }

    @Test func isIdempotentOnRepeatedRuns() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "1.5 cups flour", name: "flour", quantityValue: 1.5)
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)
        let displayTextAfterFirstRun = ingredient.displayText
        let quantityAfterFirstRun = ingredient.quantityValue

        let secondRunChangedCount = RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(secondRunChangedCount == 0)
        #expect(ingredient.displayText == displayTextAfterFirstRun)
        #expect(ingredient.quantityValue == quantityAfterFirstRun)
    }

    /// The exact 2026-08-15 bug report: a recipe imported directly from
    /// Discover left the whole raw line ("2 cups flour") jammed into
    /// `name`, with quantityValue/unit never populated. Standardize used
    /// to only fix the wheel value, leaving the raw text duplicated in
    /// name right alongside it. It should now move the amount out
    /// entirely, not copy it.
    @Test func movesAmountOutOfNameInsteadOfDuplicatingIt() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "2 cups flour", name: "2 cups flour", quantityValue: nil, unit: nil)
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        let changed = RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(changed == 1)
        #expect(ingredient.name == "Flour")
        // "cups" -> "cup": per the 2026-08-15 unit-alias table, a plural
        // now normalizes to its canonical singular rather than staying
        // as typed.
        #expect(ingredient.unit == "cup")
        #expect(ingredient.quantityValue == 2)
        #expect(ingredient.displayText == "2 cup Flour")
    }

    @Test func normalizesARangeHiddenInsideNameIntoADashRange() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "7 Bananas to 8 Bananas", name: "7 Bananas to 8 Bananas")
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(ingredient.name == "Bananas")
        #expect(ingredient.quantityValue == 7)
        #expect(ingredient.displayText == "7 - 8 Bananas")
    }

    @Test func stripsAStrayLeadingBulletFromName() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "vanilla extract", name: "• vanilla extract")
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]
        try context.save()

        let changed = RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(changed == 1)
        #expect(ingredient.name == "Vanilla Extract")
    }

    @Test func onlyTouchesRecipesInTheSpecifiedCookbook() throws {
        let context = try makeInMemoryContext()
        let cookbook = makeCookbook(in: context)
        let otherCookbook = makeCookbook(in: context)
        let recipe = makeRecipe(in: cookbook, context: context)
        let otherRecipe = makeRecipe(in: otherCookbook, context: context)

        let section = IngredientSection()
        let ingredient = Ingredient(displayText: "1.5 cups flour", name: "flour", quantityValue: 1.5)
        section.ingredients = [ingredient]
        recipe.ingredientSections = [section]

        let otherSection = IngredientSection()
        let otherIngredient = Ingredient(displayText: "1.5 cups flour", name: "flour", quantityValue: 1.5)
        otherSection.ingredients = [otherIngredient]
        otherRecipe.ingredientSections = [otherSection]

        try context.save()

        RecipeQuantityStandardizer.standardize(cookbook, modelContext: context)

        #expect(ingredient.displayText == "1 1/2 cups Flour")
        #expect(otherIngredient.displayText == "1.5 cups flour")
    }
}
