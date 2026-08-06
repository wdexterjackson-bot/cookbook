//
//  CreateHubView.swift
//  cookbook
//
//  The dashboard spec's "Create" tab: "manual recipe, paste text, import
//  link, photo/scan." Presented from a centered, elevated tab button
//  (RootTabView) rather than being a persistent tab destination itself.
//  Discover (Spoonacular/TheMealDB search) folds in here as "Search
//  Online" rather than keeping its own tab, per the confirmed navigation
//  decision. Photo/scan capture doesn't exist anywhere in this app yet
//  (a later PRD phase) — shown disabled rather than faked.
//

import SwiftUI
import SwiftData

struct CreateHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var activeSheet: ActiveSheet?

    private enum ActiveSheet: String, Identifiable {
        case manual, pasteText, searchOnline
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
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
                HStack {
                    Label("Photo / Scan", systemImage: "camera")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Coming soon")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
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
