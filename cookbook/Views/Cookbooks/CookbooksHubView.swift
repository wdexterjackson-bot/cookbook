//
//  CookbooksHubView.swift
//  cookbook
//
//  The dashboard spec's "Cookbooks" tab: "All recipe containers —
//  Personal, joined groups, MFB, with a cookbook switcher." Reuses
//  GroupCookbookView (Family) wholesale rather than rewriting its
//  content — this screen owns the switcher plus Personal cookbook
//  create/edit/delete. Family Cookbook removal isn't duplicated here —
//  GroupCookbookView already has a correct "Leave Family Cookbook" flow
//  (including the last-admin-can't-leave edge case), reached by tapping
//  into the cookbook.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct CookbooksHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]
    @Query private var allRecipes: [Recipe]
    @State private var joinedGroups: [(membership: Membership, group: FamilyGroup)] = []
    @State private var isLoading = false
    @State private var isPresentingNewPersonalCookbook = false
    @State private var isPresentingNewFamilyCookbook = false
    @State private var cookbookPendingEdit: Cookbook?
    @State private var cookbookPendingDeletion: Cookbook?
    @State private var path = NavigationPath()

    // MARK: - Backup / Restore
    @State private var cookbookPendingBackup: Cookbook?
    @State private var backupDocument: CookbookBackupDocument?
    @State private var isPresentingBackupExporter = false
    @State private var isPresentingRestoreImporter = false
    @State private var backupErrorMessage: String?
    @State private var restoreErrorMessage: String?
    @State private var restoreSuccessMessage: String?
    /// Deliberately not navigated to until the "Cookbook Restored" alert is
    /// dismissed — setting this and showing the alert in the same update
    /// both queue a presentation-affecting transition (alert popover +
    /// NavigationStack push) on top of the .fileImporter sheet's own
    /// dismissal, which reliably crashed UIKit's focus system (SIGABRT deep
    /// inside _UIFocusContainerGuideFallbackItemsContainer, observed
    /// 2026-08-08). Sequencing them — alert first, push only from the
    /// alert's own dismiss action — avoids stacking three transitions at once.
    @State private var restoredCookbookID: UUID?
    /// Set while waiting on the user to pick Overwrite vs. Add as New for
    /// a backup file that contains at least one recipe they already have
    /// (by originalRecipeID) — nil the rest of the time, including when a
    /// backup has no such overlap at all, since there's nothing to ask
    /// about then and restore proceeds straight to .addAsNew.
    @State private var pendingRestoreChoice: (data: Data, matchCount: Int)?
    @State private var isPresentingCloudRestore = false
    @State private var cloudSyncErrorMessage: String?
    @State private var syncingCookbookID: PersistentIdentifier?

    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService()
    private let photoUploadService: PersonalCookbookPhotoUploadServicing = FirebasePersonalCookbookPhotoUploadService()

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    NavigationLink {
                        FavoriteRecipesView()
                    } label: {
                        Label("Favorites", systemImage: "heart.fill")
                    }
                }

                Section("Personal") {
                    ForEach(ownedCookbooks) { cookbook in
                        // A plain value-based NavigationLink, not a
                        // destination-builder one with a .simultaneousGesture
                        // layered on for the side effect — that combination
                        // is a known SwiftUI trap where the gesture and the
                        // link's own tap recognizer compete for the row,
                        // leaving only the trailing chevron reliably
                        // tappable. Setting the active cookbook happens in
                        // the destination's .onAppear instead, so the whole
                        // row is a single, unambiguous tap target.
                        NavigationLink(value: cookbook.id) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(cookbook.title)
                                    if cookbook.storageMode == .cloudSynced {
                                        Text(lastSyncedCaption(for: cookbook))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if syncingCookbookID == cookbook.persistentModelID {
                                    Spacer()
                                    ProgressView()
                                }
                            }
                        }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    cookbookPendingDeletion = cookbook
                                }
                                Button("Edit") {
                                    cookbookPendingEdit = cookbook
                                }
                                .tint(.blue)
                                Button(cookbook.storageMode == .cloudSynced ? "Sync Now" : "Back Up") {
                                    Task { await beginBackup(cookbook) }
                                }
                                .tint(.orange)
                                .disabled(syncingCookbookID == cookbook.persistentModelID)
                            }
                    }
                }

                if !joinedGroups.isEmpty {
                    Section("Family Cookbooks") {
                        ForEach(joinedGroups, id: \.group.id) { entry in
                            NavigationLink {
                                GroupCookbookView(group: entry.group, membership: entry.membership, groupsService: groupsService)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.group.cookbookName)
                                    Text(entry.group.name)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Cookbooks")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPresentingNewPersonalCookbook = true
                        } label: {
                            Label("New Personal Cookbook", systemImage: "book.closed")
                        }
                        Button {
                            isPresentingNewFamilyCookbook = true
                        } label: {
                            Label("New Family Cookbook", systemImage: "person.3")
                        }
                        Button {
                            isPresentingRestoreImporter = true
                        } label: {
                            Label("Restore from Backup", systemImage: "arrow.counterclockwise")
                        }
                        Button {
                            isPresentingCloudRestore = true
                        } label: {
                            Label("Restore from Cloud", systemImage: "icloud.and.arrow.down")
                        }
                    } label: {
                        Label("New Cookbook", systemImage: "plus")
                    }
                    .accessibilityLabel("New Cookbook")
                }
            }
            .navigationDestination(for: UUID.self) { cookbookID in
                RecipeListView()
                    .onAppear { activeCookbookState.setActive(cookbookID) }
            }
            .task(id: accountState.currentUserID) {
                await loadJoinedGroups()
            }
            .refreshable {
                await loadJoinedGroups()
            }
            .sheet(isPresented: $isPresentingNewPersonalCookbook) {
                CookbookConfigurationView(mode: .create(ownerID: accountState.currentOwnerID))
            }
            .sheet(isPresented: $isPresentingNewFamilyCookbook) {
                CreateFamilyCookbookView(groupsService: groupsService)
            }
            .sheet(item: $cookbookPendingEdit) { cookbook in
                CookbookConfigurationView(mode: .edit(cookbook))
            }
            .sheet(isPresented: $isPresentingCloudRestore) {
                RestoreFromCloudView { restoredID in
                    path.append(restoredID)
                }
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
            .fileExporter(
                isPresented: $isPresentingBackupExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: cookbookPendingBackup.map(Self.backupFilename(for:)) ?? "Cookbook Backup"
            ) { result in
                if case .failure(let error) = result {
                    backupErrorMessage = error.localizedDescription
                }
                backupDocument = nil
                cookbookPendingBackup = nil
            }
            .fileImporter(
                isPresented: $isPresentingRestoreImporter,
                allowedContentTypes: [.json]
            ) { result in
                switch result {
                case .success(let url):
                    restore(from: url)
                case .failure(let error):
                    restoreErrorMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                restoreChoiceDialogTitle,
                isPresented: Binding(
                    get: { pendingRestoreChoice != nil },
                    set: { isPresented in if !isPresented { pendingRestoreChoice = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingRestoreChoice {
                    Button("Overwrite Existing Recipes") {
                        performRestore(data: pendingRestoreChoice.data, mode: .overwriteExisting)
                        self.pendingRestoreChoice = nil
                    }
                    Button("Add All as New") {
                        performRestore(data: pendingRestoreChoice.data, mode: .addAsNew)
                        self.pendingRestoreChoice = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingRestoreChoice = nil
                }
            }
            .alert(
                "Couldn't Back Up Cookbook",
                isPresented: Binding(
                    get: { backupErrorMessage != nil },
                    set: { if !$0 { backupErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(backupErrorMessage ?? "")
            }
            .alert(
                "Couldn't Restore Backup",
                isPresented: Binding(
                    get: { restoreErrorMessage != nil },
                    set: { if !$0 { restoreErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreErrorMessage ?? "")
            }
            .alert(
                "Cookbook Restored",
                isPresented: Binding(
                    get: { restoreSuccessMessage != nil },
                    set: { if !$0 { restoreSuccessMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    if let restoredCookbookID {
                        path.append(restoredCookbookID)
                    }
                    restoredCookbookID = nil
                }
            } message: {
                Text(restoreSuccessMessage ?? "")
            }
            .alert(
                "Couldn't Sync to the Cloud",
                isPresented: Binding(
                    get: { cloudSyncErrorMessage != nil },
                    set: { if !$0 { cloudSyncErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cloudSyncErrorMessage ?? "")
            }
        }
    }

    private var deletionConfirmationTitle: String {
        guard let cookbookPendingDeletion else { return "" }
        let count = CookbookDeletionCoordinator.recipeCount(for: cookbookPendingDeletion, in: modelContext)
        let recipeWord = count == 1 ? "recipe" : "recipes"
        return "Delete \"\(cookbookPendingDeletion.title)\"? This will permanently delete this cookbook and its \(count) \(recipeWord). This cannot be undone."
    }

    /// No fallback cookbook is required even when deleting the active (or
    /// only) one — CookbookMigrator recreates an empty "Personal Cookbook"
    /// next time one is needed, same as CookbooksListView's equivalent.
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

    private func loadJoinedGroups() async {
        guard let userID = accountState.currentUserID else {
            joinedGroups = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var groups: [(Membership, FamilyGroup)] = []
            for membership in memberships {
                if let group = try await groupsService.fetchGroup(id: membership.groupID) {
                    groups.append((membership, group))
                }
            }
            joinedGroups = groups
        } catch {
            joinedGroups = []
        }
    }

    // MARK: - Backup / Restore

    /// A cloud-synced cookbook's "Back Up" swipe action becomes "Sync Now"
    /// — a quick push to Firestore/Storage instead of the local JSON file
    /// export, per the confirmed "manual, tied to Back Up" sync design.
    /// An on-device-only cookbook keeps today's exact behavior.
    private func beginBackup(_ cookbook: Cookbook) async {
        let recipesInCookbook = allRecipes.filter {
            $0.ownerID == accountState.currentOwnerID && $0.cookbookID == cookbook.id
        }

        guard cookbook.storageMode == .cloudSynced else {
            do {
                let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipesInCookbook)
                cookbookPendingBackup = cookbook
                backupDocument = CookbookBackupDocument(data: data)
                isPresentingBackupExporter = true
            } catch {
                backupErrorMessage = error.localizedDescription
            }
            return
        }

        guard let ownerUserID = accountState.currentUserID else { return }
        syncingCookbookID = cookbook.persistentModelID
        defer { syncingCookbookID = nil }
        do {
            try await PersonalCookbookSyncCoordinator.push(
                cookbook, recipes: recipesInCookbook, ownerUserID: ownerUserID,
                syncService: syncService, photoUploadService: photoUploadService
            )
            try? modelContext.save()
        } catch {
            cloudSyncErrorMessage = error.localizedDescription
        }
    }

    private func lastSyncedCaption(for cookbook: Cookbook) -> String {
        guard let lastSyncedAt = cookbook.lastSyncedAt else { return "Never synced" }
        return "Synced \(lastSyncedAt.formatted(.relative(presentation: .named)))"
    }

    /// Pulled out to a plain function (rather than inline in the
    /// .confirmationDialog call) — a large SwiftUI body already close to
    /// its type-checking budget can time out over one more nontrivial
    /// inline ternary/string-interpolation expression, the same class of
    /// issue fixed elsewhere in this file.
    private var restoreChoiceDialogTitle: String {
        guard let pendingRestoreChoice else { return "" }
        if pendingRestoreChoice.matchCount == 1 {
            return "You already have 1 recipe from this backup. Overwrite it with the backup's version, or add it as a new copy?"
        }
        return "You already have \(pendingRestoreChoice.matchCount) recipes from this backup. Overwrite them with the backup's versions, or add them as new copies?"
    }

    /// Reads the picked file and decides whether Overwrite-vs-Add-New is
    /// even worth asking about: a backup with no recipes the owner
    /// already has (the common case — a fresh restore, or one from
    /// another device) proceeds straight to .addAsNew with no extra
    /// prompt; one that does overlap defers to pendingRestoreChoice so
    /// the confirmationDialog can ask.
    private func restore(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let matchCount = try CookbookBackupService.matchingRecipeCount(
                in: data, ownerID: accountState.currentOwnerID, modelContext: modelContext
            )
            if matchCount > 0 {
                pendingRestoreChoice = (data: data, matchCount: matchCount)
            } else {
                performRestore(data: data, mode: .addAsNew)
            }
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
    }

    private func performRestore(data: Data, mode: RecipeRestoreMode) {
        do {
            let (cookbookID, cookbookTitle, outcome) = try CookbookBackupService.restore(
                data, ownerID: accountState.currentOwnerID, modelContext: modelContext, mode: mode
            )
            restoreSuccessMessage = restoreSuccessMessage(title: cookbookTitle, outcome: outcome)
            // nil exactly when nothing new was filed into a shell cookbook
            // (a pure overwrite) — CookbookBackupService already discarded
            // that empty shell, so there's nowhere sensible to navigate.
            restoredCookbookID = cookbookID
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
    }

    private func restoreSuccessMessage(title: String, outcome: RecipeRestoreOutcome) -> String {
        let addedWord = outcome.addedCount == 1 ? "recipe" : "recipes"
        guard outcome.overwrittenCount > 0 else {
            return "Restored \"\(title)\" with \(outcome.addedCount) \(addedWord)."
        }
        let overwrittenWord = outcome.overwrittenCount == 1 ? "recipe" : "recipes"
        guard outcome.addedCount > 0 else {
            return "Updated \(outcome.overwrittenCount) existing \(overwrittenWord) from \"\(title)\"."
        }
        return "Restored \"\(title)\": \(outcome.addedCount) new \(addedWord), \(outcome.overwrittenCount) existing \(overwrittenWord) updated."
    }

    private static func backupFilename(for cookbook: Cookbook) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let sanitized = cookbook.title.components(separatedBy: invalidCharacters).joined(separator: " ")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Cookbook Backup" : trimmed
    }
}

/// Wraps a CookbookBackupService.exportData() result so it can be handed
/// to SwiftUI's .fileExporter — export-only in practice (Restore goes
/// through .fileImporter + CookbookBackupService.restore instead, since
/// that side needs no document type, just the picked file's Data), but
/// FileDocument requires read conformance too.
private struct CookbookBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let fileData = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = fileData
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

#Preview {
    CookbooksHubView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
