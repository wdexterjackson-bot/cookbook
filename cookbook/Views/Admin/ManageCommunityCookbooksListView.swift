//
//  ManageCommunityCookbooksListView.swift
//  cookbook
//
//  Administrator screen's "select the Community Cookbook you want to Edit
//  or Manage" entry point — one row per cookbook, grouped under its
//  parent group's name (a group can hold several cookbooks, so a member
//  of 3 groups where one holds 2 cookbooks sees 3 group sections and 4
//  cookbook rows total). Tapping one pushes CommunityCookbookManageView,
//  which shows editable Cookbook Settings for admins and today's
//  read-only info for a plain member. See ManageGroupsListView for the
//  group-level counterpart (Group Settings, Leave, Share QR, admins).
//

import SwiftUI

struct ManageCommunityCookbooksListView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss

    @State private var groupedEntries: [(group: FamilyGroup, membership: Membership, cookbooks: [GroupCookbook])] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let groupsService: GroupsServicing = FirestoreGroupsService()

    var body: some View {
        NavigationStack {
            List {
                if groupedEntries.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Community Cookbooks Yet",
                        systemImage: "person.3",
                        description: Text("Join or create a Community Cookbook first.")
                    )
                } else {
                    ForEach(groupedEntries, id: \.group.id) { entry in
                        Section(entry.group.name) {
                            ForEach(entry.cookbooks) { cookbook in
                                NavigationLink {
                                    CommunityCookbookManageView(group: entry.group, cookbook: cookbook, membership: entry.membership, groupsService: groupsService)
                                } label: {
                                    Text(cookbook.cookbookName)
                                }
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
            .navigationTitle("Manage Community Cookbooks")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadGroupedCookbooks()
            }
            .refreshable {
                await loadGroupedCookbooks()
            }
        }
    }

    private func loadGroupedCookbooks() async {
        guard let userID = accountState.currentUserID else {
            groupedEntries = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Admin-only — a plain member has nothing to manage here (see
            // AdministratorView, which hides this whole entry point unless
            // the user is an admin of at least one group).
            let memberships = try await groupsService.fetchMemberships(forUser: userID)
                .filter { $0.status == .active && $0.role == .admin }
            var grouped: [(FamilyGroup, Membership, [GroupCookbook])] = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                let cookbooks = try await groupsService.fetchGroupCookbooks(forGroup: membership.groupID)
                guard !cookbooks.isEmpty else { continue }
                grouped.append((group, membership, cookbooks))
            }
            groupedEntries = grouped
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ManageCommunityCookbooksListView()
        .environment(AccountState(authService: FakeAuthService()))
}
