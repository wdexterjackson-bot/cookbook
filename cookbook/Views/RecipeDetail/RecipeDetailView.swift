//
//  RecipeDetailView.swift
//  cookbook
//

import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @State private var isPresentingEdit = false
    @State private var isPresentingCookingMode = false
    @State private var isPresentingPublish = false
    @State private var cartToastMessage: String?

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
                    HStack {
                        sectionHeader("Ingredients")
                        Spacer()
                        Button("Add all to cart") {
                            addAllIngredientsToCart()
                        }
                        .font(.subheadline)
                    }
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

                sectionHeader("Notes")
                if recipe.notes.isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
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
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    recipe.isFavorite.toggle()
                    recipe.updatedAt = .now
                    saveOrRevert { recipe.isFavorite.toggle() }
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites")

                Button {
                    let previousRating = recipe.personalRating
                    recipe.personalRating = isLiked ? nil : 5
                    recipe.updatedAt = .now
                    saveOrRevert { recipe.personalRating = previousRating }
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
        .cartToast($cartToastMessage)
    }

    private func addAllIngredientsToCart() {
        let ownerID = accountState.currentOwnerID
        let sourceRecipeID = recipe.id.uuidString
        for section in recipe.ingredientSections {
            for ingredient in section.ingredients {
                CartItemStore.addFromRecipe(
                    ownerID: ownerID,
                    displayText: ingredient.displayText,
                    quantityValue: ingredient.quantityValue,
                    unit: ingredient.unit,
                    sourceRecipeID: sourceRecipeID,
                    sourceRecipeTitleSnapshot: recipe.title,
                    in: modelContext
                )
            }
        }
        showCartToast("Added all ingredients to cart")
    }

    /// Favorite/Like toggle first, save second — if the save throws, undo
    /// the toggle so the UI doesn't claim a change that didn't persist,
    /// and tell the user via the existing cart-toast overlay (a generic
    /// bottom toast despite the name, not cart-specific).
    private func saveOrRevert(undo: () -> Void) {
        do {
            try modelContext.save()
        } catch {
            undo()
            showCartToast("Couldn't save — try again")
        }
    }

    private func showCartToast(_ message: String) {
        cartToastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if cartToastMessage == message {
                cartToastMessage = nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(recipe.title)
                .font(.potluckHeadline(26))
                .foregroundStyle(Color.potluckDeepTeal)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            heroImage

            // Owner/credit line, never an editable field here. "Inspired
            // by" only shows when the recipe actually has a stamped
            // authorLineage (imported "By:" line, or the creator's own
            // name/location if they set one) — otherwise it's just "You."
            Label(lineageLabelText, systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Credit: \(lineageLabelText)")
        }
        .frame(maxWidth: .infinity)
    }

    private var lineageLabelText: String {
        if let lineage = recipe.authorLineage?.trimmingCharacters(in: .whitespacesAndNewlines), !lineage.isEmpty {
            return "Inspired by \(lineage)"
        }
        return "You"
    }

    @ViewBuilder
    private var heroImage: some View {
        #if os(iOS)
        if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
        }
        #endif
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
                    Spacer()
                    AddToCartButton(
                        ownerID: accountState.currentOwnerID,
                        sourceRecipeID: recipe.id.uuidString,
                        sourceRecipeTitleSnapshot: recipe.title,
                        displayText: ingredient.displayText,
                        quantityValue: ingredient.quantityValue,
                        unit: ingredient.unit
                    )
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
