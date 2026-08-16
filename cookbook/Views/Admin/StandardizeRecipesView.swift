//
//  StandardizeRecipesView.swift
//  cookbook
//
//  Administrator's on-demand entry point for RecipeQuantityStandardizer —
//  pick one personal cookbook, convert its recipes' amounts from the old
//  free-text decimal format to the new wheel-picker format (and
//  Title-Case ingredient names/headings). Complements RootTabView's
//  automatic first-launch prompt (which covers every not-yet-standardized
//  cookbook at once); this is for running it again anytime, or for a
//  cookbook the user skipped there.
//

import SwiftUI
import SwiftData

struct StandardizeRecipesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Query private var allCookbooks: [Cookbook]

    @State private var selectedCookbookID: UUID?
    @State private var isStandardizing = false
    @State private var resultMessage: String?

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Cookbook", selection: $selectedCookbookID) {
                        Text("Choose a Cookbook").tag(UUID?.none)
                        ForEach(ownedCookbooks) { cookbook in
                            Text(cookbook.title).tag(UUID?.some(cookbook.id))
                        }
                    }
                } footer: {
                    Text("Updates recipe amounts in this cookbook to the new whole-number-plus-fraction format (like \"1 1/2\" instead of \"1.5\") and title-cases ingredient names. Safe to run more than once — a cookbook already in the new format is left as-is.")
                }

                Section {
                    Button("Standardize Recipes") {
                        Task { await standardize() }
                    }
                    .disabled(selectedCookbookID == nil || isStandardizing)
                }

                if isStandardizing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Updating…")
                        }
                    }
                }

                if let resultMessage {
                    Section {
                        Text(resultMessage).foregroundStyle(.secondary)
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Standardize Recipes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func standardize() async {
        guard let selectedCookbookID, let cookbook = ownedCookbooks.first(where: { $0.id == selectedCookbookID }) else { return }
        isStandardizing = true
        resultMessage = nil
        // See RootTabView.standardizePendingCookbooks for why this yield
        // matters — without it, a fast run finishes within the same
        // run-loop turn and the progress row never actually renders.
        await Task.yield()
        let changedCount = RecipeQuantityStandardizer.standardize(cookbook, modelContext: modelContext)
        RecipeStandardizationState.markStandardized(cookbook.id)
        isStandardizing = false
        let outcome = changedCount == 0
            ? "\"\(cookbook.title)\" was already up to date."
            : "Updated \(changedCount) ingredient\(changedCount == 1 ? "" : "s") in \"\(cookbook.title)\"."
        resultMessage = "\(outcome) You may close this window now."
    }
}

#Preview {
    StandardizeRecipesView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
