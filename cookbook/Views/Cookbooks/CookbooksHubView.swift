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

struct CookbooksHubView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]
    @State private var joinedGroups: [(membership: Membership, group: FamilyGroup)] = []
    @State private var isLoading = false
    @State private var isPresentingNewPersonalCookbook = false
    @State private var isPresentingNewFamilyCookbook = false
    @State private var cookbookPendingEdit: Cookbook?
    @State private var cookbookPendingDeletion: Cookbook?

    private let groupsService: GroupsServicing = FirestoreGroupsService()

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    var body: some View {
        NavigationStack {
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
}

#Preview {
    CookbooksHubView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
