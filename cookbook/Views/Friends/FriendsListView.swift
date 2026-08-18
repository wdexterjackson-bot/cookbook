//
//  FriendsListView.swift
//  cookbook
//
//  Accepted friends + pending requests — structurally close to
//  MessagesView's own inbox-row pattern for the request rows. No
//  per-user display name shown for the same reason GroupAdminManagementView
//  doesn't show one either — a live cross-user profile lookup isn't a
//  capability this app has; findUserByEmail's result (name shown at
//  request time, in AddFriendView) is the one deliberate exception, since
//  that's a one-time, rate-limited, opt-in lookup, not a general capability.
//

import SwiftUI

struct FriendsListView: View {
    let friendsService: FriendsServicing
    let friendDiscoveryService: FriendDiscoveryServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friendship] = []
    @State private var pendingRequests: [FriendRequest] = []
    @State private var isLoading = false
    @State private var busyIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var isPresentingAddFriend = false

    var body: some View {
        NavigationStack {
            List {
                if !pendingRequests.isEmpty {
                    Section("Friend Requests") {
                        ForEach(pendingRequests) { request in
                            requestRow(request)
                        }
                    }
                }

                Section("Friends") {
                    if friends.isEmpty && !isLoading {
                        Text("No friends yet — add one by email or QR code.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friends) { friendship in
                            friendRow(friendship)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Friends")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                    .accessibilityLabel("Add Friend")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingAddFriend) {
                AddFriendView(friendsService: friendsService, friendDiscoveryService: friendDiscoveryService)
            }
            .task {
                await load()
            }
            .refreshable {
                await load()
            }
            .onChange(of: isPresentingAddFriend) { wasPresenting, isPresenting in
                if wasPresenting, !isPresenting {
                    Task { await load() }
                }
            }
        }
    }

    @ViewBuilder
    private func requestRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Friend request from \(shortLabel(request.senderID))")
                .font(.subheadline)
            HStack {
                Button("Accept") {
                    Task { await respond(request, accept: true) }
                }
                Button("Decline", role: .destructive) {
                    Task { await respond(request, accept: false) }
                }
            }
            .disabled(busyIDs.contains(request.id))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func friendRow(_ friendship: Friendship) -> some View {
        Text(otherUserLabel(friendship))
            #if !os(tvOS)
            .swipeActions {
                Button("Remove", role: .destructive) {
                    Task { await remove(friendship) }
                }
            }
            #endif
    }

    private func shortLabel(_ userID: String) -> String {
        "Member \(userID.suffix(6))"
    }

    private func otherUserLabel(_ friendship: Friendship) -> String {
        guard let userID = accountState.currentUserID,
              let otherID = friendship.userIDs.first(where: { $0 != userID }) else {
            return "Friend"
        }
        return shortLabel(otherID)
    }

    private func load() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        friends = (try? await friendsService.fetchFriends(forUser: userID)) ?? []
        pendingRequests = (try? await friendsService.fetchFriendRequests(forRecipient: userID)) ?? []
    }

    private func respond(_ request: FriendRequest, accept: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(request.id)
        errorMessage = nil
        defer { busyIDs.remove(request.id) }
        do {
            try await friendsService.respondToFriendRequest(request.id, accept: accept, respondingUserID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ friendship: Friendship) async {
        guard let userID = accountState.currentUserID else { return }
        errorMessage = nil
        do {
            try await friendsService.removeFriend(friendship.id, actingUserID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    FriendsListView(friendsService: InMemoryFriendsService(), friendDiscoveryService: FakeFriendDiscoveryService())
        .environment(AccountState(authService: FakeAuthService()))
}
