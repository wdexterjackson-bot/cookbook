//
//  RootTabView.swift
//  cookbook
//
//  Home dashboard spec's 5-tab navigation: Home / Cookbooks / Create /
//  Messages / Profile — replaces the earlier provisional layout. Create
//  isn't a persistent destination (it's "a centered, visually-elevated
//  tab button" per spec) — selecting it presents CreateHubView as a
//  sheet and immediately reverts the tab selection, so it never "sticks"
//  as an active tab the way a real destination would.
//

import SwiftUI
import SwiftData

private enum RootTab: Hashable {
    case home, cookbooks, create, messages, profile
}

struct RootTabView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @State private var cookbookNeedingFirstRunConfiguration: Cookbook?
    @State private var selectedTab: RootTab = .home
    @State private var previousTab: RootTab = .home
    @State private var isPresentingCreate = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RootTab.home)

            CookbooksHubView()
                .tabItem {
                    Label("Cookbooks", systemImage: "book.closed")
                }
                .tag(RootTab.cookbooks)

            Color.clear
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("Create")
                }
                .tag(RootTab.create)

            MessagesView()
                .tabItem {
                    Label("Messages", systemImage: "tray")
                }
                .tag(RootTab.messages)

            AccountView()
                .tabItem {
                    Label("Profile", systemImage: "person.crop.circle")
                }
                .tag(RootTab.profile)
        }
        .tint(Color.potluckTomato)
        .onChange(of: selectedTab) { _, newTab in
            if newTab == .create {
                isPresentingCreate = true
                selectedTab = previousTab
            } else {
                previousTab = newTab
            }
        }
        .sheet(isPresented: $isPresentingCreate) {
            CreateHubView()
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
        .environment(CookingSessionState())
}
