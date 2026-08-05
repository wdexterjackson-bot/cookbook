//
//  IngredientQuickView.swift
//  cookbook
//

import SwiftUI

struct IngredientQuickView: View {
    let recipe: Recipe
    @Binding var servingMultiplier: Double
    @Binding var checkedIngredientIDs: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $servingMultiplier, in: 0.25...4, step: 0.25) {
                        Text("Scale: \(servingMultiplier.formatted(.number.precision(.fractionLength(0...2))))×")
                    }
                    if servingMultiplier != 1 {
                        Button("Reset to Original") { servingMultiplier = 1 }
                    }
                    if !recipe.yield.isEmpty {
                        Text("Original yield: \(recipe.yield)")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Servings")
                } footer: {
                    Text("Scaling adjusts quantities below for ingredients with a recognized amount. It never changes the saved recipe, and lines without a recognized amount are shown as written.")
                }

                ForEach(recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }) { section in
                    Section(sectionTitle(section)) {
                        ForEach(section.ingredients.sorted { $0.sortOrder < $1.sortOrder }) { ingredient in
                            ingredientRow(ingredient)
                        }
                    }
                }
            }
            .navigationTitle("Ingredients")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func sectionTitle(_ section: IngredientSection) -> String {
        guard let heading = section.heading, !heading.isEmpty else { return "Ingredients" }
        return heading
    }

    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        let isChecked = checkedIngredientIDs.contains(ingredient.id)
        let text = scaledText(for: ingredient)
        return Button {
            toggle(ingredient.id)
        } label: {
            HStack {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                Text(text)
                    .strikethrough(isChecked)
                    .foregroundStyle(isChecked ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityAddTraits(isChecked ? [.isSelected] : [])
    }

    private func toggle(_ id: UUID) {
        if checkedIngredientIDs.contains(id) {
            checkedIngredientIDs.remove(id)
        } else {
            checkedIngredientIDs.insert(id)
        }
    }

    private func scaledText(for ingredient: Ingredient) -> String {
        guard let value = ingredient.quantityValue, servingMultiplier != 1 else {
            return ingredient.displayText
        }
        let scaled = value * servingMultiplier
        let formattedValue = scaled.formatted(.number.precision(.fractionLength(0...2)))
        let unit = ingredient.unit.map { " \($0)" } ?? ""
        return "\(formattedValue)\(unit) \(ingredient.name)"
    }
}
