//
//  RecipeQuantityStandardizer.swift
//  cookbook
//
//  Converts a cookbook's recipes from the old free-text decimal amount
//  format to the new wheel-picker format (whole number + common cooking
//  fraction) — both the hidden Ingredient.quantityValue (recovering
//  fractions like "1/2" the old decimal-only field silently failed to
//  parse) and the visible amount text in displayText, plus Title-Casing
//  ingredient names/section headings. Reachable two ways: the first-launch
//  prompt (RootTabView, all of an owner's not-yet-standardized personal
//  cookbooks) and "Standardize Recipes" in the Administrator tab (one
//  cookbook, user-picked, re-runnable anytime).
//

import Foundation
import SwiftData

enum RecipeQuantityStandardizer {
    /// Runs against every recipe filed under `cookbook` (matched by
    /// `cookbookID`, same scoping every other per-cookbook query in this
    /// app uses). Returns the number of ingredients actually changed —
    /// 0 means the cookbook was already in the new format, which is a
    /// safe, expected outcome of re-running this (idempotent).
    @discardableResult
    static func standardize(_ cookbook: Cookbook, modelContext: ModelContext) -> Int {
        let cookbookID = cookbook.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
        guard let recipes = try? modelContext.fetch(descriptor) else { return 0 }

        var changedCount = 0
        for recipe in recipes {
            for section in recipe.ingredientSections {
                if let newHeading = titleCased(section.heading), newHeading != section.heading {
                    section.heading = newHeading
                }
                for ingredient in section.ingredients where standardize(ingredient) {
                    changedCount += 1
                }
            }
        }
        if changedCount > 0 {
            try? modelContext.save()
        }
        return changedCount
    }

    /// Returns true if this ingredient's stored quantity, display text, or
    /// name changed.
    private static func standardize(_ ingredient: Ingredient) -> Bool {
        var changed = false

        // Broken-import signature: an amount/unit sitting inside `name`
        // itself, e.g. name == "7 Bananas to 8 Bananas" — what a recipe
        // imported directly from Discover used to leave behind (see
        // CreateEditRecipeView's .importing case), since nothing had ever
        // split it into separate fields. Standardize should "always
        // incorporate the rule from import" (2026-08-15 feedback), so
        // this reuses the exact same IngredientLineParser real imports
        // now use, rather than a second, divergent rule. Only fires when
        // the parse actually changed something — a normal, already-clean
        // name ("Flour, sifted") round-trips unchanged and is left alone,
        // so this can never clobber legitimate trailing text.
        let parsedName = IngredientLineParser.parse(ingredient.name, knownUnits: CreateEditRecipeView.commonUnits)
        if parsedName.name != ingredient.name {
            if parsedName.quantity != nil {
                // A real amount was hiding in the name — move it out and
                // rebuild the whole line from the parts, the same way
                // RecipeFileImportCoordinator composes a freshly-imported
                // one, instead of leaving the old raw text duplicated
                // alongside the now-correct wheel value.
                let snapped = WheelQuantity.nearest(to: parsedName.quantity)
                ingredient.name = parsedName.name
                ingredient.quantityValue = snapped.quantityValue
                if let unit = parsedName.unit { ingredient.unit = unit }
                ingredient.displayText = RecipeFileImportCoordinator.displayText(for: ParsedIngredientLine(
                    name: parsedName.name,
                    quantity: snapped.quantityValue,
                    unit: parsedName.unit ?? ingredient.unit,
                    rangeUpperText: parsedName.rangeUpperText
                ))
            } else {
                // No amount, just a stray leading bullet character.
                ingredient.name = parsedName.name
            }
            changed = true
        }

        // Quantity: recover/snap from whatever's already there, rewriting
        // only the leading quantity portion of displayText — never the
        // rest of the line (unit, name, any trailing author notes like
        // ", sifted") — and only when that leading portion is exactly
        // what LeadingQuantityToken found (a defensive check against
        // displayText not actually starting the way we expect). Skipped
        // when the name-based rebuild above already fired for this
        // ingredient — it already rebuilt displayText from scratch, so
        // re-processing it here would just be redundant.
        if parsedName.name == ingredient.name, let parsed = LeadingQuantityToken.parse(from: ingredient.displayText) {
            let snapped = WheelQuantity.nearest(to: parsed.value)
            if ingredient.quantityValue != snapped.quantityValue {
                ingredient.quantityValue = snapped.quantityValue
                changed = true
            }
            if ingredient.displayText.hasPrefix(parsed.matchedText) {
                let remainder = ingredient.displayText.dropFirst(parsed.matchedText.count)
                let newDisplayText = snapped.displayText.isEmpty
                    ? remainder.trimmingCharacters(in: .whitespaces)
                    : "\(snapped.displayText)\(remainder)"
                if newDisplayText != ingredient.displayText {
                    ingredient.displayText = newDisplayText
                    changed = true
                }
            }
        }

        // Name: Title Case, both the structured field and (best-effort) a
        // matching substring within displayText — a case-insensitive
        // whole-string replace of the old name for the new one, which
        // works regardless of where in displayText the name actually
        // sits (leading, after a unit, etc.) without needing to touch
        // anything else on the line.
        if let newName = titleCased(ingredient.name), newName != ingredient.name {
            if let range = ingredient.displayText.range(of: ingredient.name, options: .caseInsensitive) {
                ingredient.displayText.replaceSubrange(range, with: newName)
            }
            ingredient.name = newName
            changed = true
        }

        return changed
    }

    private static func titleCased(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return text }
        return text.capitalized
    }
}
