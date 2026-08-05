//
//  RecipeListView.swift
//  cookbook
//

import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @State private var isPresentingCreateRecipe = false
    @State private var isPresentingFilters = false
    @State private var isPresentingAccount = false
    @State private var criteria = RecipeFilterCriteria()

    /// Recipes belonging to whichever identity is currently active on this
    /// device (signed-in account, or the local guest identity) — owner-key
    /// scoping so a second person signing in on a shared device never sees
    /// the first person's recipes.
    private var ownedRecipes: [Recipe] {
        allRecipes.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var filteredRecipes: [Recipe] {
        RecipeSearch.apply(criteria, to: ownedRecipes)
    }

    var body: some View {
        NavigationStack {
            Group {
                if ownedRecipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Tap the + button to add your first recipe to your Personal Cookbook.")
                    )
                } else if filteredRecipes.isEmpty {
                    ContentUnavailableView(
                        "No Matching Recipes",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term or clear your filters.")
                    )
                } else {
                    List {
                        if criteria.hasActiveFilters {
                            Section {
                                activeFilterChips
                            }
                            .listRowInsets(EdgeInsets())
                        }
                        Section {
                            ForEach(filteredRecipes) { recipe in
                                NavigationLink {
                                    RecipeDetailView(recipe: recipe)
                                } label: {
                                    RecipeRow(recipe: recipe)
                                }
                            }
                            .onDelete(perform: deleteRecipes)
                        }
                    }
                }
            }
            .searchable(text: $criteria.searchText, prompt: "Search recipes, ingredients, tags")
            .navigationTitle("Personal Cookbook")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingCreateRecipe = true
                    } label: {
                        Label("Add Recipe", systemImage: "plus")
                    }
                    .accessibilityLabel("Add Recipe")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Picker("Sort", selection: $criteria.sort) {
                            ForEach(RecipeSortOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        Button {
                            isPresentingFilters = true
                        } label: {
                            Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    } label: {
                        Label("Sort & Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Sort and filter recipes")
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        isPresentingAccount = true
                    } label: {
                        Image(systemName: accountState.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                    }
                    .accessibilityLabel(accountState.isSignedIn ? "Account, signed in" : "Account, not signed in")
                }
            }
            .sheet(isPresented: $isPresentingCreateRecipe) {
                CreateEditRecipeView(mode: .create)
            }
            .sheet(isPresented: $isPresentingFilters) {
                RecipeFilterSheet(criteria: $criteria, availableOptions: RecipeFilterOptions(recipes: ownedRecipes))
            }
            .sheet(isPresented: $isPresentingAccount) {
                AccountView()
            }
        }
    }

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let course = criteria.course {
                    filterChip("Course: \(course)") { criteria.course = nil }
                }
                if let cuisine = criteria.cuisine {
                    filterChip("Cuisine: \(cuisine)") { criteria.cuisine = nil }
                }
                if let tag = criteria.tag {
                    filterChip("Tag: \(tag)") { criteria.tag = nil }
                }
                if let dietaryLabel = criteria.dietaryLabel {
                    filterChip("Diet: \(dietaryLabel)") { criteria.dietaryLabel = nil }
                }
                if let excludedAllergen = criteria.excludedAllergen {
                    filterChip("No \(excludedAllergen)") { criteria.excludedAllergen = nil }
                }
                if criteria.favoritesOnly {
                    filterChip("Favorites") { criteria.favoritesOnly = false }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func filterChip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .accessibilityLabel("Remove filter: \(text)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    private func deleteRecipes(at offsets: IndexSet) {
        let store = SwiftDataRecipeStore(context: modelContext)
        for index in offsets {
            try? store.delete(filteredRecipes[index])
        }
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if recipe.isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    RecipeListView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
