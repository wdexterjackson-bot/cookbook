//
//  IngredientReferenceListView.swift
//  cookbook
//
//  Read-only, grouped ingredient list — shared by CookingModePrepReviewView
//  (the prep-review page) and CookingModeView's per-step sticky panel, so
//  "what's the full ingredient list, scaled to the current serving size"
//  isn't rendered three different ways across the app. Deliberately no
//  interaction (no checkboxes, no add-to-cart) — that fuller experience
//  already exists in IngredientQuickView's sheet; this view is pure
//  quick-reference ("the recipe says 'add sugar' — how much again?").
//

import SwiftUI

struct IngredientReferenceListView: View {
    let recipe: Recipe
    var servingMultiplier: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }) { section in
                VStack(alignment: .leading, spacing: 4) {
                    if let heading = section.heading, !heading.isEmpty {
                        Text(heading)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(section.ingredients.sorted { $0.sortOrder < $1.sortOrder }) { ingredient in
                        Text(scaledText(for: ingredient))
                            .font(.body)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Mirrors IngredientQuickView.scaledText(for:) — non-scalable lines
    /// (no parsed quantityValue) are carried over exactly as written, and
    /// a scalable one is always rendered as a fraction, never a decimal
    /// (2026-08-15 feedback).
    private func scaledText(for ingredient: Ingredient) -> String {
        guard let value = ingredient.quantityValue, servingMultiplier != 1 else {
            return ingredient.displayText
        }
        let scaled = value * servingMultiplier
        let formattedValue = WheelQuantity.nearest(to: scaled).displayText
        let unit = ingredient.unit.map { " \($0)" } ?? ""
        return "\(formattedValue)\(unit) \(ingredient.name)"
    }
}
