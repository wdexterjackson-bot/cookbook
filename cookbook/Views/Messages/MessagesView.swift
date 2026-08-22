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
import SwiftData

struct MessagesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss
    @Query private var allCookbooks: [Cookbook]

    @State private var messages: [Message] = []
    @State private var adminPendingJoinRequests: [(request: JoinRequest, group: FamilyGroup)] = []
    @State private var ownJoinRequests: [(request: JoinRequest, group: FamilyGroup)] = []
    @State private var pendingInvitations: [(invitation: Invitation, group: FamilyGroup)] = []
    @State private var incomingFriendRequests: [FriendRequest] = []
    @State private var outgoingFriendRequests: [FriendRequest] = []
    @State private var pendingSharedRecipes: [SharedRecipe] = []
    @State private var outgoingSharedRecipes: [SharedRecipe] = []
    #if !os(tvOS)
    @State private var chatUnreadCounts: [String: Int] = [:]
    #endif
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var copyStatusMessage: String?
    @State private var busyIDs: Set<String> = []
    @State private var friendlyNames = FriendlyNameDirectory()
    @State private var sharedRecipePendingCookbookChoice: SharedRecipe?
    #if !os(tvOS)
    @State private var isPresentingNewChat = false
    #endif

    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let friendsService: FriendsServicing = FirestoreFriendsService()
    private let chatService: ChatServicing = FirestoreChatService()
    private let messagingService: MessagingServicing = FirestoreMessagingService()
    private let sharedRecipesService: SharedRecipesServicing = FirestoreSharedRecipesService()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()
    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    @State private var gate = EntitlementGateCoordinator()

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    var body: some View {
        NavigationStack {
            List {
                if isEverythingEmpty && !isLoading {
                    ContentUnavailableView("No Messages", systemImage: "tray")
                }

                #if !os(tvOS)
                if !chatUnreadCounts.isEmpty {
                    Section("Chats") {
                        ForEach(chatUnreadCounts.sorted { $0.key < $1.key }, id: \.key) { friendUserID, unreadCount in
                            chatRow(friendUserID: friendUserID, unreadCount: unreadCount)
                        }
                    }
                }
                #endif

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

                if !incomingFriendRequests.isEmpty {
                    Section("Friend Requests") {
                        ForEach(incomingFriendRequests) { request in
                            incomingFriendRequestRow(request)
                        }
                    }
                }

                if !outgoingFriendRequests.isEmpty {
                    Section("Your Friend Requests") {
                        ForEach(outgoingFriendRequests) { request in
                            outgoingFriendRequestRow(request)
                        }
                    }
                }

                if !pendingSharedRecipes.isEmpty {
                    Section("Recipes Shared With You") {
                        ForEach(pendingSharedRecipes) { shared in
                            sharedRecipeRow(shared)
                        }
                        if let copyStatusMessage {
                            Text(copyStatusMessage).foregroundStyle(Color.potluckSage)
                        }
                    }
                }

                if !outgoingSharedRecipes.isEmpty {
                    Section("Recipes You've Shared") {
                        ForEach(outgoingSharedRecipes) { shared in
                            outgoingSharedRecipeRow(shared)
                        }
                    }
                }

                if !ownJoinRequests.isEmpty {
                    Section("Your Requests") {
                        ForEach(ownJoinRequests, id: \.request.id) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.group.name)
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
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                #if !os(tvOS)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingNewChat = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New Message")
                }
                #endif
            }
            #if !os(tvOS)
            .sheet(isPresented: $isPresentingNewChat) {
                NewChatView(friendsService: friendsService, chatService: chatService)
            }
            #endif
            .sheet(item: $sharedRecipePendingCookbookChoice) { shared in
                PickCookbookSheet(title: "Add to Cookbook", cookbooks: ownedCookbooks) { cookbook in
                    Task { await copySharedRecipe(shared, into: cookbook) }
                }
            }
            .task(id: accountState.currentUserID) {
                await load()
            }
            .refreshable {
                await load()
            }
        }
        .entitlementGate(
            gate,
            userID: accountState.currentUserID ?? "",
            entitlementService: entitlementService,
            purchaseService: purchaseService,
            claimWriter: claimWriter
        )
    }

    private var isEverythingEmpty: Bool {
        var empty = messages.isEmpty && adminPendingJoinRequests.isEmpty && ownJoinRequests.isEmpty && pendingInvitations.isEmpty
            && incomingFriendRequests.isEmpty && outgoingFriendRequests.isEmpty && pendingSharedRecipes.isEmpty
            && outgoingSharedRecipes.isEmpty
        #if !os(tvOS)
        empty = empty && chatUnreadCounts.isEmpty
        #endif
        return empty
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
            Text(entry.group.name)
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
            Text(entry.group.name)
                .font(.headline)
            Text("You've been invited to join")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Accept") {
                    Task { await respond(entry.invitation, group: entry.group, accept: true) }
                }
                Button("Decline", role: .destructive) {
                    Task { await respond(entry.invitation, group: entry.group, accept: false) }
                }
            }
            .disabled(busyIDs.contains(entry.invitation.id))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func sharedRecipeRow(_ shared: SharedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shared.content.title)
                .font(.headline)
            Text("Shared by \(friendlyNames.label(for: shared.senderID))")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Accept") {
                    sharedRecipePendingCookbookChoice = shared
                }
                .disabled(ownedCookbooks.isEmpty)
                Button("Decline", role: .destructive) {
                    Task { await declineSharedRecipe(shared) }
                }
            }
            .disabled(busyIDs.contains(shared.id))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func outgoingSharedRecipeRow(_ shared: SharedRecipe) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(shared.content.title)
                .font(.headline)
            Text("Shared with \(friendlyNames.label(for: shared.recipientID)) — waiting for a response")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    #if !os(tvOS)
    @ViewBuilder
    private func chatRow(friendUserID: String, unreadCount: Int) -> some View {
        NavigationLink {
            ChatView(friendUserID: friendUserID, chatService: chatService)
        } label: {
            HStack {
                Text(friendlyNames.label(for: friendUserID))
                Spacer()
                Text("\(unreadCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(Color.potluckTomato))
            }
        }
    }
    #endif

    @ViewBuilder
    private func incomingFriendRequestRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Friend request from \(friendlyNames.label(for: request.senderID))")
                .font(.headline)
            HStack {
                Button("Accept") {
                    Task { await respondToFriendRequest(request, accept: true) }
                }
                Button("Decline", role: .destructive) {
                    Task { await respondToFriendRequest(request, accept: false) }
                }
            }
            .disabled(busyIDs.contains(request.id))
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func outgoingFriendRequestRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Friend request sent to \(friendlyNames.label(for: request.recipientID))")
                .font(.headline)
            Text("Waiting for a response")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Cancel", role: .destructive) {
                Task { await cancelFriendRequest(request) }
            }
            .disabled(busyIDs.contains(request.id))
        }
        .padding(.vertical, 4)
    }

    /// Each inbox section is fetched and applied independently — one
    /// section throwing (e.g. `messagingService.fetchMessages`, the
    /// newest/least-exercised of these) used to abort the whole function
    /// inside a single do/catch, leaving every other section — friend
    /// requests, invitations, join requests — blank even though their own
    /// fetches would have succeeded. Now a failure only blanks its own
    /// section and is folded into one non-blocking summary error.
    private func load() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        defer { isLoading = false }

        var failureMessages: [String] = []

        do {
            messages = try await messagingService.fetchMessages(for: userID)
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        do {
            let requests = try await groupsService.fetchJoinRequests(byRequester: userID)
            ownJoinRequests = try await attachGroups(to: requests) { $0.groupID }
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        do {
            let adminMemberships = try await groupsService.fetchMemberships(forUser: userID)
                .filter { $0.status == .active && $0.role == .admin }
            var pendingRequests: [(JoinRequest, FamilyGroup)] = []
            for membership in adminMemberships {
                let pending = try await groupsService.fetchJoinRequests(forGroup: membership.groupID)
                guard !pending.isEmpty, let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                pendingRequests.append(contentsOf: pending.map { ($0, group) })
            }
            adminPendingJoinRequests = pendingRequests
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        do {
            if let email = accountState.currentUserEmail {
                let invitations = try await groupsService.fetchInvitations(forInvitee: email)
                pendingInvitations = try await attachGroups(to: invitations) { $0.groupID }
            } else {
                pendingInvitations = []
            }
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        do {
            incomingFriendRequests = try await friendsService.fetchFriendRequests(forRecipient: userID)
            outgoingFriendRequests = try await friendsService.fetchFriendRequests(bySender: userID)
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        do {
            pendingSharedRecipes = try await sharedRecipesService.fetchSharedRecipes(forRecipient: userID)
                .filter { $0.state == .pending }
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        do {
            outgoingSharedRecipes = try await sharedRecipesService.fetchSharedRecipes(bySender: userID)
                .filter { $0.state == .pending }
        } catch {
            failureMessages.append(error.localizedDescription)
        }

        var otherUserIDs = incomingFriendRequests.map(\.senderID)
            + outgoingFriendRequests.map(\.recipientID)
            + pendingSharedRecipes.map(\.senderID)
            + outgoingSharedRecipes.map(\.recipientID)

        #if !os(tvOS)
        do {
            chatUnreadCounts = try await chatService.fetchUnreadCounts(forRecipient: userID)
            otherUserIDs += Array(chatUnreadCounts.keys)
        } catch {
            failureMessages.append(error.localizedDescription)
        }
        #endif

        await friendlyNames.load(userIDs: otherUserIDs)

        errorMessage = failureMessages.isEmpty ? nil
            : (failureMessages.count == 1 ? failureMessages[0] : "Some of your messages couldn't be loaded. Pull to refresh to try again.")
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

    private func respondToFriendRequest(_ request: FriendRequest, accept: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(request.id)
        defer { busyIDs.remove(request.id) }
        do {
            try await friendsService.respondToFriendRequest(request.id, accept: accept, respondingUserID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancelFriendRequest(_ request: FriendRequest) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(request.id)
        defer { busyIDs.remove(request.id) }
        do {
            try await friendsService.cancelFriendRequest(request.id, actingUserID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copySharedRecipe(_ shared: SharedRecipe, into cookbook: Cookbook) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(shared.id)
        errorMessage = nil
        defer { busyIDs.remove(shared.id) }
        switch RecipeCopyCoordinator.copy(shared, forUserID: userID, into: cookbook, modelContext: modelContext) {
        case .success:
            do {
                try await sharedRecipesService.markCopied(shared.id, recipientID: userID)
                copyStatusMessage = "Added \"\(shared.content.title)\" to \(cookbook.title)."
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = "Couldn't copy this recipe: \(error.localizedDescription)"
        }
    }

    private func declineSharedRecipe(_ shared: SharedRecipe) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(shared.id)
        defer { busyIDs.remove(shared.id) }
        do {
            try await sharedRecipesService.decline(shared.id, recipientID: userID)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private func respond(_ invitation: Invitation, group: FamilyGroup, accept: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        busyIDs.insert(invitation.id)
        defer { busyIDs.remove(invitation.id) }

        guard accept else {
            do {
                try await groupsService.respondToInvitation(invitation.id, accept: false, respondingUserID: userID)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
        await gate.attempt(
            .groupJoin,
            outcome: EntitlementGate.forGroupJoin(entitlement, group: group),
            recheck: { EntitlementGate.forGroupJoin($0, group: group) }
        ) {
            do {
                try await groupsService.respondToInvitation(invitation.id, accept: true, respondingUserID: userID)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    MessagesView()
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
        .modelContainer(for: Recipe.self, inMemory: true)
}
