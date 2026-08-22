//
//  FriendsListView.swift
//  cookbook
//
//  Accepted friends only — pending requests (incoming and outgoing) live
//  in Messages/the Home dashboard instead, same as join requests and
//  invitations never appear in Family either, only in Messages. Friendly
//  names come from FriendlyNameDirectory (publicProfiles) — unlike
//  GroupAdminManagementView, which still has no such lookup for group
//  members.
//

import SwiftUI

struct FriendsListView: View {
    let friendsService: FriendsServicing
    let friendDiscoveryService: FriendDiscoveryServicing
    let chatService: ChatServicing = FirestoreChatService()

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friendship] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPresentingAddFriend = false
    @State private var isPresentingMyQRCode = false
    @State private var friendlyNames = FriendlyNameDirectory()

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
        #if os(tvOS)
        Text(otherUserLabel(friendship))
        #else
        NavigationLink {
            if let userID = accountState.currentUserID, let otherID = friendship.otherUserID(than: userID) {
                ChatView(friendUserID: otherID, chatService: chatService)
            }
        } label: {
            Text(otherUserLabel(friendship))
        }
        .swipeActions {
            Button("Remove", role: .destructive) {
                Task { await remove(friendship) }
            }
        }
        #endif
    }

    private func otherUserLabel(_ friendship: Friendship) -> String {
        guard let userID = accountState.currentUserID,
              let otherID = friendship.otherUserID(than: userID) else {
            return "Friend"
        }
        return friendlyNames.label(for: otherID)
    }

    private func load() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        friends = (try? await friendsService.fetchFriends(forUser: userID)) ?? []
        let otherIDs = friends.compactMap { $0.otherUserID(than: userID) }
        await friendlyNames.load(userIDs: otherIDs)
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
