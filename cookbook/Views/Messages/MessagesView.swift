//
//  MessagesView.swift
//  cookbook
//
//  An actionable inbox merging three sources: real Message docs
//  (MessagingServicing — infrastructure is real even though nothing
//  generates these yet, that wiring is a later follow-up), join requests
//  pending your approval as an admin, invitations addressed to your
//  email, and your own outbound join requests' decided status.
//

import SwiftUI

struct MessagesView: View {
    @Environment(AccountState.self) private var accountState

    @State private var messages: [Message] = []
    @State private var adminPendingJoinRequests: [(request: JoinRequest, group: FamilyGroup)] = []
    @State private var ownJoinRequests: [(request: JoinRequest, group: FamilyGroup)] = []
    @State private var pendingInvitations: [(invitation: Invitation, group: FamilyGroup)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyIDs: Set<String> = []

    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let messagingService: MessagingServicing = FirestoreMessagingService()

    var body: some View {
        NavigationStack {
            List {
                if isEverythingEmpty && !isLoading {
                    ContentUnavailableView("No Messages", systemImage: "tray")
                }

                if !adminPendingJoinRequests.isEmpty {
                    Section("Requests to Join Your Cookbooks") {
                        ForEach(adminPendingJoinRequests, id: \.request.id) { entry in
                            joinRequestRow(entry)
                        }
                    }
                }

                if !pendingInvitations.isEmpty {
                    Section("Invitations") {
                        ForEach(pendingInvitations, id: \.invitation.id) { entry in
                            invitationRow(entry)
                        }
                    }
                }

                if !ownJoinRequests.isEmpty {
                    Section("Your Requests") {
                        ForEach(ownJoinRequests, id: \.request.id) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.group.cookbookName)
                                    .font(.headline)
                                Text(statusText(entry.request.state))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !messages.isEmpty {
                    Section("Notices") {
                        ForEach(messages) { message in
                            Text(message.type.rawValue)
                                .font(.subheadline)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Messages")
            .task(id: accountState.currentUserID) {
                await load()
            }
            .refreshable {
                await load()
            }
        }
    }

    private var isEverythingEmpty: Bool {
        messages.isEmpty && adminPendingJoinRequests.isEmpty && ownJoinRequests.isEmpty && pendingInvitations.isEmpty
    }

    private func statusText(_ state: JoinRequestState) -> String {
        switch state {
        case .pending: return "Waiting for a response"
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .cancelled: return "Cancelled"
        case .expired: return "Expired"
        }
    }

    @ViewBuilder
    private func joinRequestRow(_ entry: (request: JoinRequest, group: FamilyGroup)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.group.cookbookName)
                .font(.headline)
            Text("Someone requested to join")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Approve") {
                    Task { await decide(entry.request, approve: true) }
                }
                Button("Deny", role: .destructive) {
                    Task { await decide(entry.request, approve: false) }
                }
            }
            .disabled(busyIDs.contains(entry.request.id))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func invitationRow(_ entry: (invitation: Invitation, group: FamilyGroup)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.group.cookbookName)
                .font(.headline)
            Text("You've been invited to join")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Accept") {
                    Task { await respond(entry.invitation, accept: true) }
                }
                Button("Decline", role: .destructive) {
                    Task { await respond(entry.invitation, accept: false) }
                }
            }
            .disabled(busyIDs.contains(entry.invitation.id))
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            messages = try await messagingService.fetchMessages(for: userID)

            let requests = try await groupsService.fetchJoinRequests(byRequester: userID)
            ownJoinRequests = try await attachGroups(to: requests) { $0.groupID }

            let adminMemberships = try await groupsService.fetchMemberships(forUser: userID)
                .filter { $0.status == .active && $0.role == .admin }
            var pendingRequests: [(JoinRequest, FamilyGroup)] = []
            for membership in adminMemberships {
                let pending = try await groupsService.fetchJoinRequests(forGroup: membership.groupID)
                guard !pending.isEmpty, let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                pendingRequests.append(contentsOf: pending.map { ($0, group) })
            }
            adminPendingJoinRequests = pendingRequests

            if let email = accountState.currentUserEmail {
                let invitations = try await groupsService.fetchInvitations(forInvitee: email)
                pendingInvitations = try await attachGroups(to: invitations) { $0.groupID }
            } else {
                pendingInvitations = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func attachGroups<T>(to items: [T], groupID: (T) -> String) async throws -> [(T, FamilyGroup)] {
        var result: [(T, FamilyGroup)] = []
        for item in items {
            if let group = try await groupsService.fetchGroup(id: groupID(item)) {
                result.append((item, group))
            }
        }
        return result
    }

    private func decide(_ request: JoinRequest, approve: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(request.id)
        defer { busyIDs.remove(request.id) }
        do {
            try await groupsService.decideJoinRequest(request.id, approve: approve, decidedByUserID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func respond(_ invitation: Invitation, accept: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(invitation.id)
        defer { busyIDs.remove(invitation.id) }
        do {
            try await groupsService.respondToInvitation(invitation.id, accept: accept, respondingUserID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MessagesView()
        .environment(AccountState(authService: FakeAuthService()))
}
