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
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @State private var cartToastMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    PotluckStepper(value: $servingMultiplier, range: 0.25...4, step: 0.25) {
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
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Ingredients")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Add all to cart") {
                        addAllIngredientsToCart()
                    }
                }
            }
        }
        .cartToast($cartToastMessage)
    }

    private func addAllIngredientsToCart() {
        let ownerID = accountState.currentOwnerID
        let sourceRecipeID = recipe.id.uuidString
        do {
            for section in recipe.ingredientSections {
                for ingredient in section.ingredients {
                    let (scaledValue, scaledText) = scaled(ingredient)
                    try CartItemStore.addFromRecipe(
                        ownerID: ownerID,
                        displayText: scaledText,
                        quantityValue: scaledValue,
                        unit: ingredient.unit,
                        sourceRecipeID: sourceRecipeID,
                        sourceRecipeTitleSnapshot: recipe.title,
                        sourceIngredientID: ingredient.id,
                        in: modelContext
                    )
                }
            }
            cartToastMessage = "Added all ingredients to cart"
        } catch {
            cartToastMessage = "Couldn't add all ingredients to cart"
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            cartToastMessage = nil
        }
    }

    /// (scaled quantity, scaled display text) — mirrors scaledText(for:)'s
    /// math so the cart entry reflects "whatever serving size the recipe
    /// is currently scaled to," per the spec. Non-scalable lines (no
    /// parsed quantityValue) are carried over exactly as written.
    private func scaled(_ ingredient: Ingredient) -> (Double?, String) {
        guard let value = ingredient.quantityValue, servingMultiplier != 1 else {
            return (ingredient.quantityValue, ingredient.displayText)
        }
        let scaledValue = value * servingMultiplier
        return (scaledValue, scaledText(for: ingredient))
    }

    private func sectionTitle(_ section: IngredientSection) -> String {
        guard let heading = section.heading, !heading.isEmpty else { return "Ingredients" }
        return heading
    }

    private func ingredientRow(_ ingredient: Ingredient) -> some View {
        let isChecked = checkedIngredientIDs.contains(ingredient.id)
        let text = scaledText(for: ingredient)
        let (scaledValue, scaledDisplayText) = scaled(ingredient)
        return HStack {
            Button {
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

            Spacer()

            AddToCartButton(
                ownerID: accountState.currentOwnerID,
                sourceRecipeID: recipe.id.uuidString,
                sourceRecipeTitleSnapshot: recipe.title,
                sourceIngredientID: ingredient.id,
                displayText: scaledDisplayText,
                quantityValue: scaledValue,
                unit: ingredient.unit
            )
        }
    }

    private func toggle(_ id: UUID) {
        if checkedIngredientIDs.contains(id) {
            checkedIngredientIDs.remove(id)
        } else {
            checkedIngredientIDs.insert(id)
        }
    }

    /// Snaps the scaled amount to the nearest eighth/third and renders it
    /// as a fraction ("1 2/3"), never a decimal ("1.67") — the same
    /// wheel-quantity vocabulary amounts are entered in, so scaling a
    /// recipe never shows a precision it was never written to
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
