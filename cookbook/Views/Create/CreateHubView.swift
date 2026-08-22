//
//  CreateHubView.swift
//  cookbook
//
//  The dashboard spec's "Create" tab: "manual recipe, paste text, import
//  link, photo/scan." Presented from a centered, elevated tab button
//  (RootTabView) rather than being a persistent tab destination itself.
//  Discover (Spoonacular/TheMealDB search) folds in here as "Search
//  Online" rather than keeping its own tab, per the confirmed navigation
//  decision. Photo/Scan (RecipePhotoScanView) is iOS/iPadOS only — camera
//  capture and on-device text recognition are both UIKit/Vision, with no
//  macOS/tvOS equivalent — so the row itself is hidden there rather than
//  shown disabled.
//

import SwiftUI
import SwiftData

struct CreateHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: String, Identifiable {
        case manual, pasteText, searchOnline, newPersonalCookbook, newFamilyCookbook
        #if os(iOS)
        case photoScan
        #endif
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Recipes") {
                    Button {
                        activeSheet = .manual
                    } label: {
                        Label("Manual Recipe", systemImage: "square.and.pencil")
                    }
                    Button {
                        activeSheet = .pasteText
                    } label: {
                        Label("Paste Text", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        activeSheet = .searchOnline
                    } label: {
                        Label("Search Online", systemImage: "sparkle.magnifyingglass")
                    }
                    #if os(iOS)
                    Button {
                        activeSheet = .photoScan
                    } label: {
                        Label("Photo / Scan", systemImage: "camera")
                    }
                    #endif
                }

                Section("Cookbooks") {
                    Button {
                        activeSheet = .newPersonalCookbook
                    } label: {
                        Label("New Personal Cookbook", systemImage: "book.closed")
                    }
                    Button {
                        activeSheet = .newFamilyCookbook
                    } label: {
                        Label("New Community Cookbook", systemImage: "person.3")
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Create")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .manual, .pasteText:
                // Paste Text opens the same editor — its Import section
                // (paste + on-device AI split) already lives inside it;
                // a distinct focused entry point isn't built yet.
                CreateEditRecipeView(mode: .create)
            case .searchOnline:
                DiscoverView()
            #if os(iOS)
            case .photoScan:
                RecipePhotoScanView()
            #endif
            case .newPersonalCookbook:
                CookbookConfigurationView(mode: .create(ownerID: accountState.currentOwnerID))
            case .newFamilyCookbook:
                CreateFamilyCookbookView(groupsService: FirestoreGroupsService())
            }
        }
    }
}

#Preview {
    CreateHubView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
