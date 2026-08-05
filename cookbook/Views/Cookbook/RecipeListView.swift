//
//  RecipeListView.swift
//  cookbook
//

import SwiftUI
import SwiftData

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @Query private var allCookbooks: [Cookbook]
    @State private var isPresentingCreateRecipe = false
    @State private var isPresentingFilters = false
    @State private var isPresentingAccount = false
    @State private var isPresentingCookbookSwitcher = false
    @State private var criteria = RecipeFilterCriteria()

    private var activeCookbook: Cookbook? {
        allCookbooks.first { $0.id == activeCookbookState.activeCookbookID }
    }

    /// Recipes belonging to whichever identity is currently active on this
    /// device (signed-in account, or the local guest identity) — owner-key
    /// scoping so a second person signing in on a shared device never sees
    /// the first person's recipes — AND filed under the currently active
    /// Cookbook specifically, now that an owner can have more than one.
    private var ownedRecipes: [Recipe] {
        allRecipes.filter { $0.ownerID == accountState.currentOwnerID && $0.cookbookID == activeCookbookState.activeCookbookID }
    }

    private var filteredRecipes: [Recipe] {
        RecipeSearch.apply(criteria, to: ownedRecipes)
    }

    /// Groups filteredRecipes by the active cookbook's configured chapters,
    /// in chapter order, with a trailing "Unfiled" group for anything with
    /// no (or a since-removed) section. A cookbook with zero configured
    /// chapters falls back to one untitled group — today's flat list.
    private var groupedBySection: [(title: String?, recipes: [Recipe])] {
        guard let activeCookbook, !activeCookbook.sections.isEmpty else {
            return [(nil, filteredRecipes)]
        }

        var groups: [(title: String?, recipes: [Recipe])] = []
        let sortedSections = activeCookbook.sections.sorted { $0.sortOrder < $1.sortOrder }
        for section in sortedSections {
            let recipesInSection = filteredRecipes.filter { $0.sectionID == section.id }
            if !recipesInSection.isEmpty {
                groups.append((section.title, recipesInSection))
            }
        }

        let knownSectionIDs = Set(sortedSections.map(\.id))
        let unfiled = filteredRecipes.filter { recipe in
            guard let sectionID = recipe.sectionID else { return true }
            return !knownSectionIDs.contains(sectionID)
        }
        if !unfiled.isEmpty {
            groups.append(("Unfiled", unfiled))
        }
        return groups
    }

    var body: some View {
        NavigationStack {
            Group {
                if ownedRecipes.isEmpty {
                    ContentUnavailableView(
                        "No Recipes Yet",
                        systemImage: "fork.knife",
                        description: Text("Tap the + button to add your first recipe to \(activeCookbook?.title ?? "your cookbook").")
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
                        ForEach(Array(groupedBySection.enumerated()), id: \.offset) { _, group in
                            Section {
                                ForEach(group.recipes) { recipe in
                                    NavigationLink {
                                        RecipeDetailView(recipe: recipe)
                                    } label: {
                                        RecipeRow(recipe: recipe)
                                    }
                                    .swipeActions {
                                        Button("Delete", role: .destructive) {
                                            deleteRecipe(recipe)
                                        }
                                    }
                                }
                            } header: {
                                if let title = group.title {
                                    Text(title)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $criteria.searchText, prompt: "Search recipes, ingredients, tags")
            .navigationTitle(activeCookbook?.title ?? "Cookbook")
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
                    Button {
                        isPresentingCookbookSwitcher = true
                    } label: {
                        Label("Cookbooks", systemImage: "books.vertical")
                    }
                    .accessibilityLabel("Switch or manage cookbooks")
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
            .sheet(isPresented: $isPresentingCookbookSwitcher) {
                CookbooksListView()
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

    private func deleteRecipe(_ recipe: Recipe) {
        let store = SwiftDataRecipeStore(context: modelContext)
        try? store.delete(recipe)
    }
}

private struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if recipe.calories != nil || !recipe.dietaryLabels.isEmpty {
                    metadataRow
                }
            }
            Spacer()
            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Favorite")
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if os(iOS)
        if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            placeholderThumbnail
        }
        #else
        placeholderThumbnail
        #endif
    }

    private var placeholderThumbnail: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(0.12))
            .frame(width: 56, height: 56)
            .overlay {
                Image(systemName: "fork.knife")
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let calories = recipe.calories {
                Text("\(calories.formatted(.number.precision(.fractionLength(0)))) cal")
            }
            ForEach(recipe.dietaryLabels.prefix(2), id: \.self) { label in
                Text(label.capitalized)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.accentColor)
    }
}

#Preview {
    RecipeListView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
