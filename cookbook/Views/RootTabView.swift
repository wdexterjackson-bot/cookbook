//
//  RootTabView.swift
//  cookbook
//
//  Minimal, provisional navigation: the smallest thing that makes Discover
//  reachable. Not a final home-screen/navigation decision — that's being
//  designed separately.
//

import SwiftUI
import SwiftData

struct RootTabView: View {
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
    }
}

#Preview {
    RootTabView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
