//
//  RootTabView.swift
//  cookbook
//
//  Minimal, provisional navigation: the smallest thing that makes Discover
//  and multiple Cookbooks reachable. Not a final home-screen/navigation
//  decision — that's being designed separately.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @State private var cookbookNeedingFirstRunConfiguration: Cookbook?

    var body: some View {
        TabView {
            RecipeListView()
                .tabItem {
                    Label("My Cookbook", systemImage: "book.closed")
                }

            DiscoverView()
                .tabItem {
                    Label("Discover", systemImage: "sparkle.magnifyingglass")
                }
        }
        .sheet(item: $cookbookNeedingFirstRunConfiguration) { cookbook in
            CookbookConfigurationView(mode: .edit(cookbook))
        }
        .task(id: accountState.currentOwnerID) {
            bootstrapActiveCookbook()
        }
    }

    /// Ensures a Cookbook exists for whoever the current owner is (guest or
    /// signed-in), makes it active if nothing else is, and — for a
    /// genuinely fresh cookbook nobody has configured yet — offers the
    /// first-run configuration sheet (4E). Runs on every launch and every
    /// owner change (sign-in/out), same as RecipeOwnershipMigrator's
    /// idempotent-by-design shape.
    private func bootstrapActiveCookbook() {
        let ownerID = accountState.currentOwnerID
        let cookbook = CookbookMigrator.ensureDefaultCookbookExists(in: modelContext, ownerID: ownerID)

        if activeCookbookState.activeCookbookID == nil {
            activeCookbookState.setActive(cookbook.id)
        }

        if !cookbook.hasBeenConfigured {
            cookbookNeedingFirstRunConfiguration = cookbook
        }
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
