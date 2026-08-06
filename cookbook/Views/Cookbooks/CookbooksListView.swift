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
                        CookbookRow(cookbook: cookbook, isActive: cookbook.id == activeCookbookState.activeCookbookID)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if ownedCookbooks.count > 1 {
                            Button("Delete", role: .destructive) {
                                delete(cookbook)
                            }
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
        }
    }

    private func delete(_ cookbook: Cookbook) {
        guard let fallback = ownedCookbooks.first(where: { $0.id != cookbook.id }) else { return }

        let cookbookID = cookbook.id
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
        if let orphanedRecipes = try? modelContext.fetch(descriptor) {
            for recipe in orphanedRecipes {
                recipe.cookbookID = fallback.id
                recipe.sectionID = nil
            }
        }

        if activeCookbookState.activeCookbookID == cookbook.id {
            activeCookbookState.setActive(fallback.id)
        }

        modelContext.delete(cookbook)
        try? modelContext.save()
    }
}

private struct CookbookRow: View {
    let cookbook: Cookbook
    let isActive: Bool

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
        } else {
            placeholderCover
        }
        #else
        placeholderCover
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
