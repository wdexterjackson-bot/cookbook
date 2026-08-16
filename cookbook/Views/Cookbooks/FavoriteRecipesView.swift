//
//  FavoriteRecipesView.swift
//  cookbook
//
//  Reachable from the Cookbooks tab — every recipe the user has hearted
//  (Recipe.isFavorite), across all of their personal Cookbooks, in one
//  flat list rather than needing to hunt through each cookbook
//  separately. Reuses RecipeRow for the same thumbnail/metadata styling
//  every other recipe list already has.
//

import SwiftUI
import SwiftData

struct FavoriteRecipesView: View {
    @Environment(AccountState.self) private var accountState
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @Query private var allCookbooks: [Cookbook]

    private var favoriteRecipes: [Recipe] {
        allRecipes.filter { $0.ownerID == accountState.currentOwnerID && $0.isFavorite }
    }

    var body: some View {
        Group {
            if favoriteRecipes.isEmpty {
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "heart",
                    description: Text("Tap the heart on any recipe to add it here.")
                )
            } else {
                List {
                    ForEach(favoriteRecipes) { recipe in
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
                .potluckHiddenScrollBackground()
                .background(Color.potluckCream)
            }
        }
        .navigationTitle("Favorites")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func cookbookTitle(for recipe: Recipe) -> String? {
        allCookbooks.first { $0.id == recipe.cookbookID }?.title
    }
}

#Preview {
    NavigationStack {
        FavoriteRecipesView()
    }
    .modelContainer(for: Recipe.self, inMemory: true)
    .environment(AccountState(authService: FakeAuthService()))
}
