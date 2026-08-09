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

        // Quantity: recover/snap from whatever's already there, rewriting
        // only the leading quantity portion of displayText — never the
        // rest of the line (unit, name, any trailing author notes like
        // ", sifted") — and only when that leading portion is exactly
        // what LeadingQuantityToken found (a defensive check against
        // displayText not actually starting the way we expect).
        if let parsed = LeadingQuantityToken.parse(from: ingredient.displayText) {
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
