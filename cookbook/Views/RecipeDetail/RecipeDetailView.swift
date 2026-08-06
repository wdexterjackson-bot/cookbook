//
//  RecipeDetailView.swift
//  cookbook
//

import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @State private var isPresentingEdit = false
    @State private var isPresentingCookingMode = false
    @State private var isPresentingPublish = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.body)
                }

                metadataRow

                if !recipe.ingredientSections.isEmpty {
                    sectionHeader("Ingredients")
                    ForEach(recipe.ingredientSections.sorted(by: { $0.sortOrder < $1.sortOrder })) { section in
                        ingredientSection(section)
                    }
                }

                if !recipe.stepSections.isEmpty {
                    sectionHeader("Steps")
                    ForEach(recipe.stepSections.sorted(by: { $0.sortOrder < $1.sortOrder })) { section in
                        stepSection(section)
                    }
                }

                if !recipe.notes.isEmpty {
                    sectionHeader("Notes")
                    Text(recipe.notes)
                }

                NutritionSummaryView(
                    calories: recipe.calories,
                    proteinGrams: recipe.proteinGrams,
                    fatGrams: recipe.fatGrams,
                    carbsGrams: recipe.carbsGrams,
                    sugarGrams: recipe.sugarGrams,
                    fiberGrams: recipe.fiberGrams,
                    sodiumMilligrams: recipe.sodiumMilligrams
                )
            }
            .padding()
        }
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    recipe.isFavorite.toggle()
                    recipe.updatedAt = .now
                    try? modelContext.save()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites")

                Button {
                    recipe.personalRating = isLiked ? nil : 5
                    recipe.updatedAt = .now
                    try? modelContext.save()
                } label: {
                    Image(systemName: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                }
                .accessibilityLabel(isLiked ? "Unlike" : "Like")

                Button("Edit") {
                    isPresentingEdit = true
                }

                Button {
                    isPresentingCookingMode = true
                } label: {
                    Label("Start Cooking", systemImage: "flame")
                }
                .accessibilityLabel("Start Cooking")

                ShareLink(item: RecipeTextFormatter.plainText(for: recipe)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share Recipe")

                Button {
                    isPresentingPublish = true
                } label: {
                    Image(systemName: "person.3")
                }
                .accessibilityLabel("Publish to a Family Cookbook")
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            CreateEditRecipeView(mode: .edit(recipe))
        }
        .sheet(isPresented: $isPresentingCookingMode) {
            CookingModeView(recipe: recipe)
        }
        .sheet(isPresented: $isPresentingPublish) {
            PublishToFamilyCookbookView(
                recipe: recipe,
                groupsService: FirestoreGroupsService(),
                publicationsService: FirestorePublicationsService(),
                photoUploadService: FirebaseRecipePhotoUploadService()
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Owner is always shown, never an editable field — even though
            // in Phase 1 it's just "You" on every recipe (PRD COOK-001).
            Label("You", systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Owner: You")
        }
    }

    /// A quick, distinct signal from Favorite — a single tap sets a fixed
    /// high rating rather than opening a full 1-5 star picker. Uses the
    /// existing personalRating field rather than adding a new isLiked flag.
    private var isLiked: Bool {
        recipe.personalRating != nil
    }

    private var metadataRow: some View {
        HStack(spacing: 16) {
            if !recipe.yield.isEmpty {
                Label(recipe.yield, systemImage: "person.2")
            }
            if let totalTime = recipe.totalTimeMinutes {
                Label("\(totalTime) min", systemImage: "clock")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 8)
    }

    private func ingredientSection(_ section: IngredientSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let heading = section.heading, !heading.isEmpty {
                Text(heading)
                    .font(.headline)
            }
            ForEach(section.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder })) { ingredient in
                HStack(alignment: .top) {
                    Text("•")
                    Text(ingredient.displayText)
                    if ingredient.isOptional {
                        Text("(optional)")
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stepSection(_ section: StepSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = section.heading, !heading.isEmpty {
                Text(heading)
                    .font(.headline)
            }
            ForEach(Array(section.steps.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .fontWeight(.semibold)
                    Text(step.text)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1): \(step.text)")
            }
        }
    }
}

#Preview {
    RecipeDetailPreviewContainer()
}

private struct RecipeDetailPreviewContainer: View {
    @State private var recipe = Recipe(ownerID: "preview", title: "Skillet Cornbread", summary: "Crispy edges, tender center.")

    var body: some View {
        NavigationStack {
            RecipeDetailView(recipe: recipe)
        }
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
    }
}
