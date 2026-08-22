//
//  ManageGroupsListView.swift
//  cookbook
//
//  Administrator screen's "Manage Groups" entry — one row per Family/
//  Group the user is an active member of (not per cookbook; a group with
//  several cookbooks still shows once here — see ManageCommunityCookbooksListView
//  for the per-cookbook counterpart, grouped under the same group names).
//  Tapping a row pushes ManageGroupView, which shows editable Group
//  Settings for admins and today's read-only info + Share QR + Leave for
//  a plain member.
//

import SwiftUI

struct ManageGroupsListView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [(membership: Membership, group: FamilyGroup)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let groupsService: GroupsServicing = FirestoreGroupsService()

    var body: some View {
        NavigationStack {
            List {
                if entries.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Groups Yet",
                        systemImage: "person.3",
                        description: Text("Join or create a Community Cookbook first.")
                    )
                } else {
                    ForEach(entries, id: \.group.id) { entry in
                        NavigationLink {
                            ManageGroupView(group: entry.group, membership: entry.membership, groupsService: groupsService)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.group.name)
                                Text(entry.group.locationText)
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
            .navigationTitle("Manage Groups")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadGroups()
            }
            .refreshable {
                await loadGroups()
            }
        }
    }

    private func loadGroups() async {
        guard let userID = accountState.currentUserID else {
            entries = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var loaded: [(Membership, FamilyGroup)] = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                loaded.append((membership, group))
            }
            entries = loaded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ManageGroupsListView()
        .environment(AccountState(authService: FakeAuthService()))
}
