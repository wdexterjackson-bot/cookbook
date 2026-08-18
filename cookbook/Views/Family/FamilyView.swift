//
//  FamilyView.swift
//  cookbook
//
//  Lists the signed-in user's Family Cookbooks and is the entry point for
//  creating a new one or finding an existing public one. Publishing a
//  personal recipe INTO a Family Cookbook is deliberately not in this
//  pass — see GroupCookbookView's empty state.
//

import SwiftUI

struct FamilyView: View {
    @Environment(AccountState.self) private var accountState

    @State private var entries: [(membership: Membership, group: FamilyGroup, cookbook: GroupCookbook)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPresentingCreate = false
    @State private var isPresentingSearch = false

    private let groupsService: GroupsServicing = FirestoreGroupsService()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Family Cookbooks Yet",
                        systemImage: "person.3",
                        description: Text("Create one, or find an existing one to request to join.")
                    )
                } else {
                    ForEach(entries, id: \.cookbook.id) { entry in
                        NavigationLink {
                            GroupCookbookView(group: entry.group, cookbook: entry.cookbook, membership: entry.membership, groupsService: groupsService)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.cookbook.cookbookName)
                                    .font(.headline)
                                Text("\(entry.group.name) · \(entry.group.locationText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Family")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isPresentingCreate = true
                        } label: {
                            Label("Create a Family Cookbook", systemImage: "plus")
                        }
                        Button {
                            isPresentingSearch = true
                        } label: {
                            Label("Find a Family Cookbook", systemImage: "magnifyingglass")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Family Cookbook actions")
                }
            }
            .sheet(isPresented: $isPresentingCreate) {
                CreateFamilyCookbookView(groupsService: groupsService)
            }
            .sheet(isPresented: $isPresentingSearch) {
                PublicGroupSearchView(groupsService: groupsService)
            }
            .task(id: accountState.currentUserID) {
                await loadEntries()
            }
            .refreshable {
                await loadEntries()
            }
        }
    }

    private func loadEntries() async {
        guard let userID = accountState.currentUserID else {
            entries = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var loaded: [(Membership, FamilyGroup, GroupCookbook)] = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                let cookbooks = try await groupsService.fetchGroupCookbooks(forGroup: membership.groupID)
                loaded.append(contentsOf: cookbooks.map { (membership, group, $0) })
            }
            entries = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    FamilyView()
        .environment(AccountState(authService: FakeAuthService()))
}
