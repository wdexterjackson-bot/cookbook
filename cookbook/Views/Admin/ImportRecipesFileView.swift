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
#if os(iOS)
import UIKit
#endif

struct ImportRecipesFileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Query private var allCookbooks: [Cookbook]

    @State private var selectedCookbookID: UUID?
    @State private var isPresentingFilePicker = false
    @State private var pendingFileText: String?
    @State private var importSession = RecipeImportSession()
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
                        .disabled(selectedCookbookID == nil || importSession.phase != .idle)
                    } footer: {
                        Text("A plain text or PDF file with one or more recipes — see Recipe_Import_Format.md for the format. This may take several minutes for large files — please keep this screen open until it finishes.")
                    }
                }

                if let progressDescription {
                    Section {
                        HStack {
                            if let progressFraction {
                                ProgressView(value: progressFraction)
                            } else {
                                ProgressView()
                            }
                            Text(progressDescription)
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
                    ImportReviewView(preview: preview, cookbook: cookbook, ownerID: accountState.currentOwnerID, importSession: importSession)
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
        // Spans the whole flow (extraction + parsing + review) since this
        // view stays mounted the entire time — ImportReviewView is
        // presented as its nested sheet, never replacing it — matching
        // the confirmed decision that the user must stay on this screen
        // until Save or Abort.
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        #endif
    }

    private var progressDescription: String? {
        switch importSession.phase {
        case .idle:
            return nil
        case .extracting(let page, let total):
            guard total > 0 else { return "Reading file…" }
            return "Extracting page \(page) of \(total)… (\(percentString(page, total)))"
        case .parsing(let chunk, let total):
            guard total > 0 else { return "Parsing recipes…" }
            return "Parsing recipe \(chunk) of \(total)… (\(percentString(chunk, total)))"
        case .saving:
            return "Saving…"
        }
    }

    private func percentString(_ completed: Int, _ total: Int) -> String {
        let percent = Int((Double(completed) / Double(total) * 100).rounded())
        return "\(percent)%"
    }

    private var progressFraction: Double? {
        switch importSession.phase {
        case .idle, .saving:
            return nil
        case .extracting(let page, let total):
            return total > 0 ? Double(page) / Double(total) : nil
        case .parsing(let chunk, let total):
            return total > 0 ? Double(chunk) / Double(total) : nil
        }
    }

    private func handleFileSelection(_ result: Result<URL, Error>) {
        // Guarded (not an unconditional reset) so this never writes to a
        // sheet-presentation-driving var in the same synchronous scope as
        // resolveAuthorLineageAndImport() below potentially setting
        // isPresentingAuthorPrompt — two such writes stacked inside one
        // .fileImporter completion handler is the exact shape that crashed
        // UIKit's focus system elsewhere in this app (CookbooksHubView's
        // restore flow, fixed 2026-08-08). preview can't actually be
        // non-nil here in practice (the review sheet isn't reachable while
        // the file picker is up), so this guard is nearly always a no-op —
        // it's defensive, not a behavior change.
        if preview != nil { preview = nil }
        errorMessage = nil
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let url):
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Couldn't open that file."
                return
            }
            importSession.phase = .extracting(page: 0, of: 0)
            Task {
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    pendingFileText = try await RecipeFileTextExtractor.extractText(from: url) { page, total in
                        importSession.phase = .extracting(page: page, of: total)
                    }
                    resolveAuthorLineageAndImport()
                } catch {
                    importSession.phase = .idle
                    errorMessage = error.localizedDescription
                }
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
        importSession.phase = .parsing(chunk: 0, of: 0)
        Task {
            let result = await RecipeFileImportCoordinator.parseRecipes(
                from: pendingFileText,
                defaultAuthorLineage: defaultAuthorLineage,
                lineImportService: lineImportService
            ) { chunk, total in
                importSession.phase = .parsing(chunk: chunk, of: total)
            }
            importSession.phase = .idle
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
