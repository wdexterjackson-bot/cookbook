//
//  ShareRecipeWithFriendView.swift
//  cookbook
//
//  RecipeDetailView's "Share with a Friend" entry point — pick a friend,
//  tap to share. The recipient sees it as a pending share in Messages
//  (mirroring how a friend request or invitation shows up there), and can
//  copy it into one of their own cookbooks from there, same shape as
//  Copy-to-Personal from a Community Cookbook.
//

import SwiftUI

struct ShareRecipeWithFriendView: View {
    let recipe: Recipe
    let friendsService: FriendsServicing
    let sharedRecipesService: SharedRecipesServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @State private var friends: [Friendship] = []
    @State private var isLoading = false
    @State private var busyFriendshipID: String?
    @State private var sharedFriendshipIDs: Set<String> = []
    @State private var errorMessage: String?
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
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Share with a Friend")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadFriends()
            }
        }
    }

    @ViewBuilder
    private func friendRow(_ friendship: Friendship) -> some View {
        let isShared = sharedFriendshipIDs.contains(friendship.id)
        Button {
            Task { await share(with: friendship) }
        } label: {
            HStack {
                Text(otherUserLabel(friendship))
                Spacer()
                if isShared {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.potluckSage)
                }
            }
        }
        .disabled(busyFriendshipID != nil)
    }

    private func otherUserLabel(_ friendship: Friendship) -> String {
        guard let userID = accountState.currentUserID,
              let otherID = friendship.otherUserID(than: userID) else {
            return "Friend"
        }
        return friendlyNames.label(for: otherID)
    }

    private func loadFriends() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }
        friends = (try? await friendsService.fetchFriends(forUser: userID)) ?? []
        let otherIDs = friends.compactMap { $0.otherUserID(than: userID) }
        await friendlyNames.load(userIDs: otherIDs)
    }

    private func share(with friendship: Friendship) async {
        guard let userID = accountState.currentUserID,
              let otherID = friendship.otherUserID(than: userID) else { return }
        busyFriendshipID = friendship.id
        errorMessage = nil
        defer { busyFriendshipID = nil }
        do {
            let content = PublicationContentSnapshot.make(from: recipe)
                .attributingSenderIfUnattributed(accountState.currentUserDisplayName)
            try await sharedRecipesService.shareRecipe(
                content: content,
                sourceRecipeID: recipe.id.uuidString,
                from: userID,
                to: otherID
            )
            sharedFriendshipIDs.insert(friendship.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ShareRecipeWithFriendView(
        recipe: Recipe(ownerID: "preview", title: "Skillet Cornbread", summary: "Crispy edges."),
        friendsService: InMemoryFriendsService(),
        sharedRecipesService: InMemorySharedRecipesService()
    )
    .environment(AccountState(authService: FakeAuthService()))
}
