//
//  SearchHubView.swift
//  cookbook
//
//  The new "Search" tab — every recipe the user owns, across all of their
//  personal Cookbooks, in one searchable list (unlike RecipeListView's own
//  .searchable, which is scoped to just the currently active Cookbook).
//  Reuses RecipeSearch/RecipeFilterCriteria/RecipeFilterSheet and RecipeRow
//  so results, sorting, and filtering all behave identically to what's
//  already established elsewhere — this is the same search, just widened
//  to every cookbook at once.
//
//  A scope Picker above the search bar switches between "My Recipes" (the
//  above) and "Public Cookbooks" — the latter embeds
//  PublicGroupSearchContent directly (not the sheet-oriented
//  PublicGroupSearchView, which wraps its own NavigationStack — nesting a
//  second one inside this tab's own NavigationStack would swallow
//  navigation, same failure mode documented on PublicGroupSearchContent
//  itself).
//

import SwiftUI
import SwiftData

private enum SearchScope: String, CaseIterable, Identifiable {
    case myRecipes = "My Recipes"
    case publicCookbooks = "Public Cookbooks"

    var id: String { rawValue }
}

struct SearchHubView: View {
    @Environment(AccountState.self) private var accountState
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @Query private var allCookbooks: [Cookbook]

    @State private var scope: SearchScope = .myRecipes
    @State private var criteria = RecipeFilterCriteria()
    @State private var isPresentingFilters = false
    #if os(iOS)
    @State private var isPresentingScanner = false
    #endif
    @State private var scanResultMessage: String?
    @State private var scanErrorMessage: String?

    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let friendsService: FriendsServicing = FirestoreFriendsService()

    private var ownedRecipes: [Recipe] {
        allRecipes.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var results: [Recipe] {
        RecipeSearch.apply(criteria, to: ownedRecipes)
    }

    private var isBrowsing: Bool {
        criteria.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !criteria.hasActiveFilters
    }

    var body: some View {
        NavigationStack {
            Group {
                switch scope {
                case .myRecipes:
                    myRecipesContent
                        .searchable(text: $criteria.searchText, prompt: "Search all your recipes")
                case .publicCookbooks:
                    PublicGroupSearchContent(groupsService: groupsService)
                }
            }
            .potluckHubBackground()
            .safeAreaInset(edge: .top) {
                Picker("Search Scope", selection: $scope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .background(Color.potluckCream)
            }
            .navigationTitle("Search")
            .toolbar {
                if scope == .myRecipes {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isPresentingFilters = true
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle\(criteria.hasActiveFilters ? ".fill" : "")")
                        }
                        .accessibilityLabel("Filters")
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel("Scan QR Code")
                }
                #endif
            }
            .sheet(isPresented: $isPresentingFilters) {
                RecipeFilterSheet(criteria: $criteria, availableOptions: RecipeFilterOptions(recipes: ownedRecipes))
            }
            #if os(iOS)
            .sheet(isPresented: $isPresentingScanner) {
                QRCodeScannerView { payload in
                    Task { await handleScannedPayload(payload) }
                }
            }
            #endif
            .alert("Sent", isPresented: Binding(
                get: { scanResultMessage != nil },
                set: { if !$0 { scanResultMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanResultMessage ?? "")
            }
            .alert("Couldn't Complete Request", isPresented: Binding(
                get: { scanErrorMessage != nil },
                set: { if !$0 { scanErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanErrorMessage ?? "")
            }
        }
    }

    private func handleScannedPayload(_ payload: QRCodePayload) async {
        guard let userID = accountState.currentUserID else { return }
        do {
            switch payload {
            case .group(let groupID):
                _ = try await groupsService.requestToJoin(groupID: groupID, requesterID: userID, note: nil)
                scanResultMessage = "Your request to join has been sent."
            case .friend(let friendUserID):
                guard friendUserID != userID else {
                    scanErrorMessage = "That's your own QR code."
                    return
                }
                _ = try await friendsService.sendFriendRequest(from: userID, to: friendUserID)
                scanResultMessage = "Friend request sent."
            }
        } catch GroupsServiceError.alreadyMember {
            scanErrorMessage = "You're already a member of this cookbook."
        } catch FriendsServiceError.alreadyFriends {
            scanErrorMessage = "You're already friends."
        } catch {
            scanErrorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var myRecipesContent: some View {
        if isBrowsing {
            ContentUnavailableView(
                "Search Your Recipes",
                systemImage: "magnifyingglass",
                description: Text("Search across every cookbook at once — by title, ingredient, tag, or who a recipe is credited to.")
            )
        } else if results.isEmpty {
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
                ForEach(results) { recipe in
                    NavigationLink {
                        RecipeDetailView(recipe: recipe)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            RecipeRow(recipe: recipe)
                            if let cookbookTitle = cookbookTitle(for: recipe) {
                                Text(cookbookTitle)
                                    .font(.caption2)
                                    .foregroundStyle(Color.potluckSage)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .potluckHiddenScrollBackground()
        }
    }

    private func cookbookTitle(for recipe: Recipe) -> String? {
        allCookbooks.first { $0.id == recipe.cookbookID }?.title
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
}

#Preview {
    SearchHubView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
