//
//  CookingModePrepReviewView.swift
//  cookbook
//
//  Cooking Mode's first page: review every ingredient and an AI-generated
//  summary of what to do before starting (equipment needed, whether to
//  preheat the oven, etc.) — confirmed here, then "Start Cooking" advances
//  to the first step. The summary generates once, on-device, then caches
//  on Recipe.prepSummary so repeat visits are instant (see
//  RecipePrepSummaryServicing). If generation isn't available (no Apple
//  Intelligence on this device, or the Simulator) or hasn't happened yet,
//  this page just shows the ingredient list with no summary section —
//  never an error message, confirmed decision.
//

import SwiftData
import SwiftUI

struct CookingModePrepReviewView: View {
    let recipe: Recipe
    @Binding var servingMultiplier: Double
    let onStartCooking: () -> Void

    var prepSummaryService: RecipePrepSummaryServicing = FoundationModelsPrepSummaryService()

    @Environment(\.modelContext) private var modelContext
    @State private var isGenerating = false

    /// Fixed row count rather than a single flowing column — lets the
    /// ingredient card have a defined size/shape and scroll horizontally
    /// when a recipe has more ingredients than fit, instead of pushing
    /// "Start Cooking" further down the page.
    private let ingredientGridRows = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let prepSummary = recipe.prepSummary, !prepSummary.isEmpty {
                    prepSummaryCard(prepSummary)
                } else if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Preparing summary…")
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Ingredients")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        PotluckStepper(value: $servingMultiplier, range: 0.25...4, step: 0.25) {
                            Text("Scale: \(servingMultiplier.formatted(.number.precision(.fractionLength(0...2))))×")
                                .font(.subheadline)
                        }
                        .fixedSize()
                    }
                    if servingMultiplier != 1 {
                        Button("Reset to Original") { servingMultiplier = 1 }
                            .font(.caption)
                    }
                    ScrollView(.horizontal) {
                        LazyHGrid(rows: ingredientGridRows, alignment: .top, spacing: 20) {
                            ForEach(flattenedIngredientEntries, id: \.id) { entry in
                                Text(entry.text)
                                    .font(.body)
                                    .frame(minWidth: 140, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .frame(height: 240)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                }

                Button {
                    onStartCooking()
                } label: {
                    Text("Start Cooking")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
        }
        .task {
            await generateSummaryIfNeeded()
        }
    }

    @ViewBuilder
    private func prepSummaryCard(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Before You Start", systemImage: "checklist")
                .font(.headline)
            Text(summary)
                .fixedSize(horizontal: false, vertical: true)
            if prepSummaryService.isAvailable {
                Button("Regenerate") {
                    recipe.prepSummary = nil
                    Task { await generateSummaryIfNeeded() }
                }
                .font(.caption)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.potluckSunflower.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
    }

    /// Mirrors IngredientReferenceListView.scaledText(for:)/
    /// IngredientQuickView.scaledText(for:) — a section heading is folded
    /// into the line itself (rather than a separate grid cell) since a
    /// fixed-row-count grid has no clean way to render a heading spanning
    /// multiple columns.
    private var flattenedIngredientEntries: [(id: UUID, text: String)] {
        let sortedSections = recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        var entries: [(id: UUID, text: String)] = []
        for section in sortedSections {
            let heading = (section.heading?.isEmpty == false) ? section.heading : nil
            let sortedIngredients = section.ingredients.sorted { $0.sortOrder < $1.sortOrder }
            for ingredient in sortedIngredients {
                let scaled = scaledText(for: ingredient)
                entries.append((ingredient.id, heading.map { "\($0): \(scaled)" } ?? scaled))
            }
        }
        return entries
    }

    /// Fraction, never a decimal, same as IngredientQuickView/
    /// IngredientReferenceListView's copies of this (2026-08-15 feedback).
    private func scaledText(for ingredient: Ingredient) -> String {
        guard let value = ingredient.quantityValue, servingMultiplier != 1 else {
            return ingredient.displayText
        }
        let scaled = value * servingMultiplier
        let formattedValue = WheelQuantity.nearest(to: scaled).displayText
        let unit = ingredient.unit.map { " \($0)" } ?? ""
        return "\(formattedValue)\(unit) \(ingredient.name)"
    }

    private func flattenedIngredientLines() -> [String] {
        let sortedSections = recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        var lines: [String] = []
        for section in sortedSections {
            let sortedIngredients = section.ingredients.sorted { $0.sortOrder < $1.sortOrder }
            for ingredient in sortedIngredients {
                lines.append(ingredient.displayText)
            }
        }
        return lines
    }

    private func flattenedStepLines() -> [String] {
        let sortedSections = recipe.stepSections.sorted { $0.sortOrder < $1.sortOrder }
        var lines: [String] = []
        for section in sortedSections {
            let sortedSteps = section.steps.sorted { $0.sortOrder < $1.sortOrder }
            for step in sortedSteps {
                lines.append(step.text)
            }
        }
        return lines
    }

    private func generateSummaryIfNeeded() async {
        guard recipe.prepSummary == nil, prepSummaryService.isAvailable else { return }
        let input = RecipePrepSummaryInput(
            title: recipe.title,
            ingredientLines: flattenedIngredientLines(),
            stepLines: flattenedStepLines()
        )
        guard !input.ingredientLines.isEmpty || !input.stepLines.isEmpty else { return }

        isGenerating = true
        defer { isGenerating = false }
        do {
            let summary = try await prepSummaryService.generateSummary(for: input)
            recipe.prepSummary = summary
            try? modelContext.save()
        } catch {
            // Graceful omission, by design — no error UI here. The section
            // simply doesn't appear; the ingredient list and Start Cooking
            // button are still fully usable.
        }
    }
}

#Preview {
    let recipe = Recipe(ownerID: "preview", title: "Skillet Cornbread")
    let section = IngredientSection()
    section.ingredients = [
        Ingredient(displayText: "2 cups cornmeal", name: "cornmeal", quantityValue: 2, unit: "cups", sortOrder: 0),
        Ingredient(displayText: "1 cup buttermilk", name: "buttermilk", quantityValue: 1, unit: "cup", sortOrder: 1),
    ]
    recipe.ingredientSections = [section]
    return NavigationStack {
        CookingModePrepReviewView(recipe: recipe, servingMultiplier: .constant(1), onStartCooking: {})
    }
    .modelContainer(for: Recipe.self, inMemory: true)
}
