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

    private let groupsService: GroupsServicing = FirestoreGroupsService()

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
                        NavigationLink(cookbook.title, value: cookbook.id)
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    cookbookPendingDeletion = cookbook
                                }
                                Button("Edit") {
                                    cookbookPendingEdit = cookbook
                                }
                                .tint(.blue)
                                Button("Back Up") {
                                    beginBackup(cookbook)
                                }
                                .tint(.orange)
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
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreSuccessMessage ?? "")
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

    private func beginBackup(_ cookbook: Cookbook) {
        let recipesInCookbook = allRecipes.filter {
            $0.ownerID == accountState.currentOwnerID && $0.cookbookID == cookbook.id
        }
        do {
            let data = try CookbookBackupService.exportData(for: cookbook, recipes: recipesInCookbook)
            cookbookPendingBackup = cookbook
            backupDocument = CookbookBackupDocument(data: data)
            isPresentingBackupExporter = true
        } catch {
            backupErrorMessage = error.localizedDescription
        }
    }

    private func restore(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let cookbook = try CookbookBackupService.restore(data, ownerID: accountState.currentOwnerID, modelContext: modelContext)
            // Queried directly against modelContext (not the view's own
            // @Query snapshot) so this reflects what restore() just saved
            // without depending on SwiftUI's own refresh timing.
            let cookbookID = cookbook.id
            let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.cookbookID == cookbookID })
            let restoredRecipeCount = (try? modelContext.fetchCount(descriptor)) ?? 0
            let recipeWord = restoredRecipeCount == 1 ? "recipe" : "recipes"
            restoreSuccessMessage = "Restored \"\(cookbook.title)\" with \(restoredRecipeCount) \(recipeWord)."
            path.append(cookbook.id)
        } catch {
            restoreErrorMessage = error.localizedDescription
        }
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
