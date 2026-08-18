//
//  FriendsListView.swift
//  cookbook
//
//  Accepted friends only — pending requests (incoming and outgoing) live
//  in Messages/the Home dashboard instead, same as join requests and
//  invitations never appear in Family either, only in Messages. No
//  per-user display name shown for the same reason
//  GroupAdminManagementView doesn't show one either — a live cross-user
//  profile lookup isn't a capability this app has; findUserByEmail's
//  result (name shown at request time, in AddFriendView) is the one
//  deliberate exception, since that's a one-time, rate-limited, opt-in
//  lookup, not a general capability.
//

import SwiftUI

struct FriendsListView: View {
    let friendsService: FriendsServicing
    let friendDiscoveryService: FriendDiscoveryServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friendship] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPresentingAddFriend = false
    @State private var isPresentingMyQRCode = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        isPresentingMyQRCode = true
                    } label: {
                        Label("My QR Code", systemImage: "qrcode")
                    }
                } footer: {
                    Text("Share this so a friend can add you instantly by scanning it.")
                }

                Section {
                    if friends.isEmpty && !isLoading {
                        Text("No friends yet — add one by email or QR code.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(friends) { friendship in
                            friendRow(friendship)
                        }
                    }
                } footer: {
                    Text("Pending friend requests show up in Messages, on the Home dashboard.")
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
            .sheet(isPresented: $isPresentingMyQRCode) {
                if let userID = accountState.currentUserID {
                    QRCodeDisplayView(
                        payload: .friend(id: userID),
                        title: "Your Friend Code",
                        subtitle: "Friends can scan this to send you a friend request."
                    )
                }
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

    private func otherUserLabel(_ friendship: Friendship) -> String {
        guard let userID = accountState.currentUserID,
              let otherID = friendship.userIDs.first(where: { $0 != userID }) else {
            return "Friend"
        }
        return "Member \(otherID.suffix(6))"
    }

    private func load() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        friends = (try? await friendsService.fetchFriends(forUser: userID)) ?? []
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
