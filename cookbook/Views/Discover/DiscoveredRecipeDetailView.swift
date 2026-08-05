//
//  DiscoveredRecipeDetailView.swift
//  cookbook
//
//  Loads full details (nutrition included) on demand — search results stay
//  lightweight to keep Spoonacular quota cheap; this is the one call per
//  recipe that costs more, and it's cached indefinitely once made.
//

import SwiftUI

struct DiscoveredRecipeDetailView: View {
    let recipe: DiscoveredRecipe
    let service: MealSearchServicing

    @State private var detailed: DiscoveredRecipe?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isPresentingImport = false

    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView()
                    .padding(.top, 80)
            } else if let errorMessage {
                ContentUnavailableView(
                    "Couldn't Load Recipe",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .padding(.top, 40)
            } else if let detailed {
                content(for: detailed)
            }
        }
        .navigationTitle(recipe.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if let detailed {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingImport = true
                    } label: {
                        Label("Add to My Cookbook", systemImage: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add to My Cookbook")
                    .disabled(detailed.ingredients.isEmpty && detailed.steps.isEmpty)
                }
            }
        }
        .sheet(isPresented: $isPresentingImport) {
            if let detailed {
                CreateEditRecipeView(mode: .importing(detailed))
            }
        }
        .task {
            await load()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            detailed = try await service.fetchDetails(externalID: recipe.externalID)
        } catch MealSearchError.quotaExceeded {
            errorMessage = "Today's free quota is used up — try again tomorrow."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func content(for recipe: DiscoveredRecipe) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heroImage(for: recipe)

            VStack(alignment: .leading, spacing: 16) {
                if let summary = recipe.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                }

                metadataRow(for: recipe)

                if !recipe.dietFlags.isEmpty {
                    dietFlagsRow(recipe.dietFlags)
                }

                if let nutrition = recipe.nutrition {
                    NutritionSummaryView(
                        calories: nutrition.calories,
                        proteinGrams: nutrition.proteinGrams,
                        fatGrams: nutrition.fatGrams,
                        carbsGrams: nutrition.carbsGrams,
                        sugarGrams: nutrition.sugarGrams,
                        fiberGrams: nutrition.fiberGrams,
                        sodiumMilligrams: nutrition.sodiumMilligrams
                    )
                }

                if !recipe.ingredients.isEmpty {
                    sectionHeader("Ingredients")
                    ForEach(recipe.ingredients) { ingredient in
                        Text("• \(ingredient.displayText)")
                    }
                }

                if !recipe.steps.isEmpty {
                    sectionHeader("Steps")
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1).")
                                .fontWeight(.semibold)
                            Text(step)
                        }
                    }
                }

                Text(recipe.attributionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func heroImage(for recipe: DiscoveredRecipe) -> some View {
        if let imageURL = recipe.imageURL.flatMap(URL.init) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipped()
        }
    }

    private func metadataRow(for recipe: DiscoveredRecipe) -> some View {
        HStack(spacing: 16) {
            if let servings = recipe.servings {
                Label("Serves \(servings)", systemImage: "person.2")
            }
            if let readyInMinutes = recipe.readyInMinutes {
                Label("\(readyInMinutes) min", systemImage: "clock")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func dietFlagsRow(_ flags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(flags, id: \.self) { flag in
                    Text(flag.capitalized)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                        .foregroundStyle(.green)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 4)
    }
}
