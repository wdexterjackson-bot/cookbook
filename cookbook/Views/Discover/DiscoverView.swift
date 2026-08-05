//
//  DiscoverView.swift
//  cookbook
//
//  Dual-source by design: Spoonacular ("Search") is the only source that
//  can honor diet/allergen filters, but its free tier is 50 points/day, so
//  it's reserved for deliberate searches. TheMealDB ("Browse") is free and
//  effectively unlimited, so random/browse discovery lives there instead
//  of spending Spoonacular quota on idle scrolling.
//

import SwiftUI
import SwiftData

struct DiscoverView: View {
    enum SourceMode: String, CaseIterable, Identifiable {
        case search = "Search"
        case browse = "Browse"
        var id: String { rawValue }
    }

    @State private var sourceMode: SourceMode = .search
    @State private var query = ""
    @State private var diet: DietPreference = DietaryPreferencesStore.current().defaultDiet
    @State private var excludedAllergens: Set<AllergenPreference> = DietaryPreferencesStore.current().excludedAllergens
    @State private var isPresentingPreferences = false
    @State private var results: [DiscoveredRecipe] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var hasSearchedOnce = false

    private let spoonacular: MealSearchServicing = SpoonacularMealSearchService()
    private let theMealDB: MealSearchServicing = TheMealDBMealSearchService()

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $sourceMode) {
                    ForEach(SourceMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                if sourceMode == .search {
                    searchFiltersBar
                }

                if sourceMode == .search, QuotaTracker.isLow {
                    quotaLowBanner
                }

                resultsArea

                attributionFooter
            }
            .navigationTitle("Discover")
            .toolbar {
                if sourceMode == .browse {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await loadBrowse() }
                        } label: {
                            Label("Shuffle", systemImage: "shuffle")
                        }
                    }
                }
            }
            .sheet(isPresented: $isPresentingPreferences) {
                DietaryPreferencesView(diet: $diet, excludedAllergens: $excludedAllergens)
            }
            .task(id: sourceMode) {
                if sourceMode == .browse, results.isEmpty {
                    await loadBrowse()
                }
            }
        }
    }

    @ViewBuilder
    private var resultsArea: some View {
        if isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView(
                "Something Went Wrong",
                systemImage: "exclamationmark.triangle",
                description: Text(errorMessage)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView(
                sourceMode == .search ? "Search for Recipes" : "Discover Something New",
                systemImage: sourceMode == .search ? "magnifyingglass" : "shuffle",
                description: Text(sourceMode == .search
                    ? (hasSearchedOnce ? "No matches — try different words or filters." : "Try a dish, ingredient, or cuisine.")
                    : "Tap Shuffle for a random meal idea.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(results) { recipe in
                        NavigationLink {
                            DiscoveredRecipeDetailView(recipe: recipe, service: service(for: recipe.source))
                        } label: {
                            DiscoveredRecipeCard(recipe: recipe)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
        }
    }

    private var searchFiltersBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Search recipes (e.g. chicken tacos)", text: $query)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await performSearch() } }
                Button("Search") { Task { await performSearch() } }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Menu {
                        Picker("Diet", selection: $diet) {
                            ForEach(DietPreference.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Label(diet == .none ? "Any Diet" : diet.label, systemImage: "leaf")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        isPresentingPreferences = true
                    } label: {
                        Label(
                            excludedAllergens.isEmpty ? "No Allergens Excluded" : "\(excludedAllergens.count) Allergen\(excludedAllergens.count == 1 ? "" : "s") Excluded",
                            systemImage: "exclamationmark.shield"
                        )
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var quotaLowBanner: some View {
        Label("Spoonacular search quota is low today — results may be limited until it resets.", systemImage: "exclamationmark.triangle")
            .font(.caption)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
    }

    private var attributionFooter: some View {
        Text(sourceMode == .search ? "Recipe data powered by Spoonacular" : "Recipe data from TheMealDB")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
    }

    private func service(for source: MealSource) -> MealSearchServicing {
        source == .spoonacular ? spoonacular : theMealDB
    }

    private func performSearch() async {
        isLoading = true
        errorMessage = nil
        hasSearchedOnce = true
        defer { isLoading = false }
        do {
            results = try await spoonacular.search(query: query, diet: diet, excludedAllergens: excludedAllergens)
        } catch MealSearchError.quotaExceeded {
            errorMessage = "Today's free search quota is used up. Try again tomorrow, or switch to Browse."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadBrowse() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            results = try await theMealDB.browseRandom(count: 8)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DiscoveredRecipeCard: View {
    let recipe: DiscoveredRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            cardImage
                .frame(height: 120)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(recipe.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var cardImage: some View {
        if let imageURL = recipe.imageURL.flatMap(URL.init) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                Image(systemName: "fork.knife")
                    .foregroundStyle(.secondary)
            }
    }
}

#Preview {
    DiscoverView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
