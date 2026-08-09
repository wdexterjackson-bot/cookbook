//
//  CookbooksListView.swift
//  cookbook
//
//  The provisional switcher — functional, not the shelf visual the user
//  is designing separately (same "smallest thing that works" spirit as
//  the Discover tab bar in milestone 3D).
//

import SwiftUI
import SwiftData

struct CookbooksListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query private var allCookbooks: [Cookbook]
    @State private var isPresentingCreate = false
    @State private var cookbookPendingEdit: Cookbook?
    @State private var cookbookPendingDeletion: Cookbook?

    private var ownedCookbooks: [Cookbook] {
        allCookbooks
            .filter { $0.ownerID == accountState.currentOwnerID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(ownedCookbooks) { cookbook in
                    Button {
                        activeCookbookState.setActive(cookbook.id)
                        dismiss()
                    } label: {
                        CookbookRow(
                            cookbook: cookbook,
                            isActive: cookbook.id == activeCookbookState.activeCookbookID,
                            recipeCount: CookbookDeletionCoordinator.recipeCount(for: cookbook, in: modelContext)
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            cookbookPendingDeletion = cookbook
                        }
                        Button("Edit") {
                            cookbookPendingEdit = cookbook
                        }
                        .tint(.blue)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Cookbooks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingCreate = true
                    } label: {
                        Label("New Cookbook", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingCreate) {
                CookbookConfigurationView(mode: .create(ownerID: accountState.currentOwnerID))
            }
            .sheet(item: $cookbookPendingEdit) { cookbook in
                CookbookConfigurationView(mode: .edit(cookbook))
            }
            .confirmationDialog(
                deletionConfirmationTitle,
                isPresented: Binding(
                    get: { cookbookPendingDeletion != nil },
                    set: { isPresented in if !isPresented { cookbookPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let cookbookPendingDeletion {
                    Button("Delete", role: .destructive) {
                        delete(cookbookPendingDeletion)
                        self.cookbookPendingDeletion = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    cookbookPendingDeletion = nil
                }
            }
        }
    }

    private var deletionConfirmationTitle: String {
        guard let cookbookPendingDeletion else { return "" }
        let count = CookbookDeletionCoordinator.recipeCount(for: cookbookPendingDeletion, in: modelContext)
        let recipeWord = count == 1 ? "recipe" : "recipes"
        return "Delete \"\(cookbookPendingDeletion.title)\"? This will permanently delete this cookbook and its \(count) \(recipeWord). This cannot be undone."
    }

    /// No longer needs a fallback cookbook to reassign recipes into (see
    /// CookbookDeletionCoordinator), so this works even when it's the
    /// user's only cookbook — CookbookMigrator recreates an empty
    /// "Personal Cookbook" next time one is needed.
    private func delete(_ cookbook: Cookbook) {
        if activeCookbookState.activeCookbookID == cookbook.id {
            if let fallback = ownedCookbooks.first(where: { $0.id != cookbook.id }) {
                activeCookbookState.setActive(fallback.id)
            } else {
                activeCookbookState.reset()
            }
        }

        CookbookDeletionCoordinator.deleteCookbookAndItsRecipes(cookbook, in: modelContext)
    }
}

private struct CookbookRow: View {
    let cookbook: Cookbook
    let isActive: Bool
    let recipeCount: Int

    var body: some View {
        HStack(spacing: 12) {
            coverThumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(cookbook.title)
                    .font(.headline)
                Text("\(cookbook.sections.count) chapter\(cookbook.sections.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(recipeCount)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: cookbook.coverColorHex))
                    .accessibilityLabel("Active cookbook")
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var coverThumbnail: some View {
        #if os(iOS)
        if let filename = cookbook.coverImageFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        } else if let style = CookbookCoverStyleCatalog.style(named: cookbook.coverStyleImageName) {
            Image(style.imageAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholderCover
        }
        #else
        if let style = CookbookCoverStyleCatalog.style(named: cookbook.coverStyleImageName) {
            Image(style.imageAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            placeholderCover
        }
        #endif
    }

    private var placeholderCover: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(hex: cookbook.coverColorHex))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: "book.closed.fill")
                    .foregroundStyle(.white)
            }
    }
}
