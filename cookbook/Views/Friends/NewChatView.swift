//
//  NewChatView.swift
//  cookbook
//
//  MessagesView's "compose" entry point — until now Messages could only
//  ever receive (friend requests, invitations, shared recipes); this is
//  the one way to actually start sending something, by picking a friend
//  and opening their ChatView. Not on tvOS, same as ChatView itself (see
//  its own doc comment — no keyboard, no text-entry story there).
//

#if !os(tvOS)
import SwiftUI

struct NewChatView: View {
    let friendsService: FriendsServicing
    let chatService: ChatServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friendship] = []
    @State private var isLoading = false
    @State private var friendlyNames = FriendlyNameDirectory()

    var body: some View {
        NavigationStack {
            List {
                if friends.isEmpty && !isLoading {
                    Text("Add a friend first — Friends is under More.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(friends) { friendship in
                        friendRow(friendship)
                    }
                }
            }
            .navigationTitle("New Message")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                await loadFriends()
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friendship: Friendship) -> some View {
        if let userID = accountState.currentUserID, let otherID = friendship.otherUserID(than: userID) {
            NavigationLink {
                ChatView(friendUserID: otherID, chatService: chatService)
            } label: {
                Text(friendlyNames.label(for: otherID))
            }
        }
    }

    private func loadFriends() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        friends = (try? await friendsService.fetchFriends(forUser: userID)) ?? []
        let otherIDs = friends.compactMap { $0.otherUserID(than: userID) }
        await friendlyNames.load(userIDs: otherIDs)
    }
}

#Preview {
    NewChatView(friendsService: InMemoryFriendsService(), chatService: InMemoryChatService())
        .environment(AccountState(authService: FakeAuthService()))
}
#endif
