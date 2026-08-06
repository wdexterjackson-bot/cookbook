//
//  CookbooksHubView.swift
//  cookbook
//
//  The dashboard spec's "Cookbooks" tab: "All recipe containers —
//  Personal, joined groups, MFB, with a cookbook switcher." A thin
//  wrapper reusing RecipeListView (Personal) and GroupCookbookView
//  (Family) wholesale rather than rewriting their content — this screen
//  is just the switcher.
//

import SwiftUI
import SwiftData

struct CookbooksHubView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]
    @State private var joinedGroups: [(membership: Membership, group: FamilyGroup)] = []
    @State private var isLoading = false

    private let groupsService: GroupsServicing = FirestoreGroupsService()

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    var body: some View {
        NavigationStack {
            List {
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
        }
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
