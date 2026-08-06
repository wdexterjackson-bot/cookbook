//
//  ImportRecipesFileView.swift
//  cookbook
//
//  Bulk recipe import — pick a cookbook, pick a file, parse each recipe
//  block with the same on-device AI single-recipe paste-import already
//  uses (RecipeLineImportServicing), via RecipeFileImportCoordinator. See
//  Recipe_Import_Format.md for the expected file format.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportRecipesFileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Query private var allCookbooks: [Cookbook]

    @State private var selectedCookbookID: UUID?
    @State private var isPresentingFilePicker = false
    @State private var pendingFileText: String?
    @State private var isImporting = false
    @State private var importResult: RecipeFileImportResult?
    @State private var errorMessage: String?
    @State private var isPresentingAuthorPrompt = false
    @State private var authorPromptWasHandled = false

    private let lineImportService: RecipeLineImportServicing = FoundationModelsLineImportService()
    private let userProfileService: UserProfileServicing = FirestoreUserProfileService()

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Import Into") {
                    Picker("Cookbook", selection: $selectedCookbookID) {
                        Text("Choose a Cookbook").tag(UUID?.none)
                        ForEach(ownedCookbooks) { cookbook in
                            Text(cookbook.title).tag(UUID?.some(cookbook.id))
                        }
                    }
                }

                if !lineImportService.isAvailable {
                    Section {
                        Text("AI recipe import isn't available on this device — this needs Apple Intelligence turned on, which isn't supported in every region or on every device.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button("Choose File") {
                            isPresentingFilePicker = true
                        }
                        .disabled(selectedCookbookID == nil || isImporting)
                    } footer: {
                        Text("A plain text file with one or more recipes — see Recipe_Import_Format.md for the format.")
                    }
                }

                if isImporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Importing…")
                        }
                    }
                }

                if let importResult {
                    Section("Results") {
                        Text("\(importResult.importedTitles.count) recipe\(importResult.importedTitles.count == 1 ? "" : "s") imported.")
                        if !importResult.failedChunks.isEmpty {
                            Text("\(importResult.failedChunks.count) couldn't be imported:")
                                .foregroundStyle(.secondary)
                            ForEach(importResult.failedChunks, id: \.self) { snippet in
                                Text(snippet)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Import Recipes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(isPresented: $isPresentingFilePicker, allowedContentTypes: [.plainText]) { result in
                handleFileSelection(result)
            }
            .sheet(isPresented: $isPresentingAuthorPrompt, onDismiss: {
                if !authorPromptWasHandled {
                    runImport(defaultAuthorLineage: "Anonymous")
                }
                authorPromptWasHandled = false
            }) {
                RecipeAuthorPromptView(
                    onSaveWithName: { name, location in
                        authorPromptWasHandled = true
                        isPresentingAuthorPrompt = false
                        if let userID = accountState.currentUserID {
                            Task {
                                try? await accountState.updateDisplayName(name)
                                if let location {
                                    try? await userProfileService.setLocation(location, userID: userID)
                                }
                            }
                        }
                        runImport(defaultAuthorLineage: location.map { "\(name) of \($0.formatted)" } ?? name)
                    },
                    onSaveAnonymous: {
                        authorPromptWasHandled = true
                        isPresentingAuthorPrompt = false
                        runImport(defaultAuthorLineage: "Anonymous")
                    }
                )
            }
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        importResult = nil
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Couldn't open that file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                errorMessage = "Couldn't read that file as text."
                return
            }
            pendingFileText = text
            resolveAuthorLineageAndImport()
        }
    }

    /// Resolved once for the whole file, not per recipe — an
    /// Anonymous/name prompt for every recipe in a multi-recipe file would
    /// be disruptive. A chunk's own "By:" line still overrides this,
    /// per-recipe, inside RecipeFileImportCoordinator.
    private func resolveAuthorLineageAndImport() {
        if let displayName = accountState.currentUserDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
            if let userID = accountState.currentUserID {
                Task {
                    let location = try? await userProfileService.fetchLocation(userID: userID)
                    runImport(defaultAuthorLineage: location.map { "\(displayName) of \($0.formatted)" } ?? displayName)
                }
            } else {
                runImport(defaultAuthorLineage: displayName)
            }
        } else {
            isPresentingAuthorPrompt = true
        }
    }

    private func runImport(defaultAuthorLineage: String?) {
        guard let pendingFileText, let selectedCookbookID,
              let cookbook = ownedCookbooks.first(where: { $0.id == selectedCookbookID }) else {
            return
        }
        isImporting = true
        Task {
            let result = await RecipeFileImportCoordinator.importRecipes(
                from: pendingFileText,
                into: cookbook,
                ownerID: accountState.currentOwnerID,
                defaultAuthorLineage: defaultAuthorLineage,
                lineImportService: lineImportService,
                modelContext: modelContext
            )
            importResult = result
            isImporting = false
            self.pendingFileText = nil
        }
    }
}

#Preview {
    ImportRecipesFileView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
