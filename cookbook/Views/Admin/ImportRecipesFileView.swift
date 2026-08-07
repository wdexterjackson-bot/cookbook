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
    @State private var isParsing = false
    @State private var preview: RecipeFileImportPreview?
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
                        .disabled(selectedCookbookID == nil || isParsing)
                    } footer: {
                        Text("A plain text or PDF file with one or more recipes — see Recipe_Import_Format.md for the format.")
                    }
                }

                if isParsing {
                    Section {
                        HStack {
                            ProgressView()
                            Text("Reading recipes…")
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
            .fileImporter(isPresented: $isPresentingFilePicker, allowedContentTypes: [.plainText, .pdf]) { result in
                handleFileSelection(result)
            }
            .sheet(isPresented: Binding(
                get: { preview != nil },
                set: { isPresented in if !isPresented { preview = nil } }
            )) {
                if let preview, let cookbook = ownedCookbooks.first(where: { $0.id == selectedCookbookID }) {
                    ImportReviewView(preview: preview, cookbook: cookbook, ownerID: accountState.currentOwnerID)
                }
            }
            .sheet(isPresented: $isPresentingAuthorPrompt, onDismiss: {
                if !authorPromptWasHandled {
                    runParse(defaultAuthorLineage: "Anonymous")
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
                        runParse(defaultAuthorLineage: location.map { "\(name) of \($0.formatted)" } ?? name)
                    },
                    onSaveAnonymous: {
                        authorPromptWasHandled = true
                        isPresentingAuthorPrompt = false
                        runParse(defaultAuthorLineage: "Anonymous")
                    }
                )
            }
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        preview = nil
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
            do {
                pendingFileText = try RecipeFileTextExtractor.extractText(from: url)
                resolveAuthorLineageAndImport()
            } catch {
                errorMessage = error.localizedDescription
            }
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
                    runParse(defaultAuthorLineage: location.map { "\(displayName) of \($0.formatted)" } ?? displayName)
                }
            } else {
                runParse(defaultAuthorLineage: displayName)
            }
        } else {
            isPresentingAuthorPrompt = true
        }
    }

    /// Parsing only — nothing is written to modelContext here. A
    /// successful parse hands the drafts to ImportReviewView, which is
    /// the only place RecipeFileImportCoordinator.commit gets called,
    /// once the user has reviewed and approved them.
    private func runParse(defaultAuthorLineage: String?) {
        guard let pendingFileText else { return }
        isParsing = true
        Task {
            let result = await RecipeFileImportCoordinator.parseRecipes(
                from: pendingFileText,
                defaultAuthorLineage: defaultAuthorLineage,
                lineImportService: lineImportService
            )
            isParsing = false
            self.pendingFileText = nil
            if result.drafts.isEmpty && result.failedChunks.isEmpty {
                errorMessage = "No recipes found in that file — make sure each recipe starts with a \"Name:\" line."
            } else {
                preview = result
            }
        }
    }
}

#Preview {
    ImportRecipesFileView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
