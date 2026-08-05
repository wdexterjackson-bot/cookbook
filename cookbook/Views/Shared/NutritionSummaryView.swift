//
//  NutritionSummaryView.swift
//  cookbook
//
//  Shared between DiscoveredRecipeDetailView (Discover) and RecipeDetailView
//  (a saved recipe) — same layout, driven by plain optionals rather than a
//  Discover-specific type, since a saved Recipe's nutrition fields are
//  scalar @Model properties, not a DiscoveredNutrition struct. Renders
//  nothing at all if every value is nil — "blank if unavailable," not a
//  row of zeros.
//

import SwiftUI

struct NutritionSummaryView: View {
    let calories: Double?
    let proteinGrams: Double?
    let fatGrams: Double?
    let carbsGrams: Double?
    let sugarGrams: Double?
    let fiberGrams: Double?
    let sodiumMilligrams: Double?

    private var hasAnyValue: Bool {
        calories != nil || proteinGrams != nil || fatGrams != nil || carbsGrams != nil
            || sugarGrams != nil || fiberGrams != nil || sodiumMilligrams != nil
    }

    var body: some View {
        if hasAnyValue {
            VStack(alignment: .leading, spacing: 8) {
                Text("Nutrition (per serving)")
                    .font(.title3.bold())
                    .padding(.top, 4)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    stat("Calories", calories, unit: "kcal")
                    stat("Protein", proteinGrams, unit: "g")
                    stat("Fat", fatGrams, unit: "g")
                    stat("Carbs", carbsGrams, unit: "g")
                    stat("Sugar", sugarGrams, unit: "g")
                    stat("Fiber", fiberGrams, unit: "g")
                    stat("Sodium", sodiumMilligrams, unit: "mg")
                }
            }
        }
    }

    @ViewBuilder
    private func stat(_ label: String, _ value: Double?, unit: String) -> some View {
        if let value {
            VStack(spacing: 2) {
                Text(value.formatted(.number.precision(.fractionLength(0))))
                    .font(.headline)
                Text("\(label) (\(unit))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value.formatted(.number.precision(.fractionLength(0)))) \(unit)")
        }
    }
}

#Preview {
    NutritionSummaryView(
        calories: 478, proteinGrams: 24, fatGrams: 29, carbsGrams: 15,
        sugarGrams: 13, fiberGrams: 2, sodiumMilligrams: 887
    )
    .padding()
}
