//
//  GroupAdminManagementView.swift
//  cookbook
//
//  Reached from GroupCookbookView's settings. Shows each active member's
//  role with a Make/Remove Administrator action — GroupPolicy.
//  isLastActiveAdmin blocks demoting the last one, matching the same
//  invariant leaveGroup already enforces. No per-member display name is
//  shown, consistent with the rest of this app (e.g. MessagesView's own
//  join-request rows say "Someone requested to join," not a name) — a
//  live cross-user profile lookup isn't a capability this app has.
//

import SwiftUI

struct GroupAdminManagementView: View {
    let group: FamilyGroup
    let groupsService: GroupsServicing

    @Environment(AccountState.self) private var accountState
    @State private var memberships: [Membership] = []
    @State private var isLoading = false
    @State private var busyMembershipIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var pendingRemoval: Membership?

    private var activeMemberships: [Membership] {
        memberships.filter { $0.status == .active }.sorted { $0.joinedAt < $1.joinedAt }
    }

    var body: some View {
        List {
            Section {
                if activeMemberships.isEmpty && !isLoading {
                    Text("No members yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(activeMemberships) { membership in
                        memberRow(membership)
                    }
                }
            } footer: {
                Text("The last remaining administrator can't be removed — promote someone else first.")
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
        .navigationTitle("Administrators")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadMemberships()
        }
        .refreshable {
            await loadMemberships()
        }
        .confirmationDialog(
            "Remove this member from the group?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let pendingRemoval {
                    Task { await removeMember(pendingRemoval) }
                }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("They'll lose access to this group's cookbooks immediately. They can still be re-invited or ask to rejoin later.")
        }
    }

    @ViewBuilder
    private func memberRow(_ membership: Membership) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(membership.userID == accountState.currentUserID ? "You" : "Member \(membership.userID.suffix(6))")
                Text(membership.role.rawValue.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(membership.role == .admin ? "Remove Admin" : "Make Admin") {
                Task { await toggleAdmin(membership) }
            }
            .font(.caption)
            .disabled(busyMembershipIDs.contains(membership.id))
            if membership.userID != accountState.currentUserID {
                Button("Remove", role: .destructive) {
                    pendingRemoval = membership
                }
                .font(.caption)
                .disabled(busyMembershipIDs.contains(membership.id))
            }
        }
        .padding(.vertical, 2)
    }

    private func loadMemberships() async {
        isLoading = true
        defer { isLoading = false }
        memberships = (try? await groupsService.fetchMemberships(forGroup: group.id)) ?? []
    }

    private func toggleAdmin(_ membership: Membership) async {
        guard let actingUserID = accountState.currentUserID else { return }
        let newRole: MembershipRole = membership.role == .admin ? .member : .admin
        busyMembershipIDs.insert(membership.id)
        errorMessage = nil
        defer { busyMembershipIDs.remove(membership.id) }
        do {
            try await groupsService.updateRole(groupID: group.id, userID: membership.userID, newRole: newRole, actingUserID: actingUserID)
            await loadMemberships()
        } catch GroupsServiceError.lastAdminCannotLeaveOrBeDemoted {
            errorMessage = "You're the last administrator — promote someone else before removing yourself."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeMember(_ membership: Membership) async {
        guard let actingUserID = accountState.currentUserID else { return }
        busyMembershipIDs.insert(membership.id)
        errorMessage = nil
        defer { busyMembershipIDs.remove(membership.id) }
        do {
            try await groupsService.removeMember(groupID: group.id, userID: membership.userID, actingUserID: actingUserID)
            await loadMemberships()
        } catch GroupsServiceError.lastAdminCannotLeaveOrBeDemoted {
            errorMessage = "You're the last administrator — promote someone else before removing them."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        GroupAdminManagementView(
            group: FamilyGroup(
                id: "group-1", slug: "group-1", name: "Barrentines", description: "", type: "Family",
                locationText: "Memphis, TN", structuredRegion: nil, coverImageURL: nil, visibility: .publicGroup,
                createdByUserID: "alice", createdByDisplayName: "Alice", createdAt: .now, status: .active,
                allowsMemberInvites: false, approvalPolicy: .anyAdministrator, isMFB: false
            ),
            groupsService: InMemoryGroupsService()
        )
        .environment(AccountState(authService: FakeAuthService()))
    }
}
