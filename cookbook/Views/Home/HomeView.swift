//
//  HomeView.swift
//  cookbook
//
//  The real Home dashboard (Sketch C "Potluck" spec, Aug 6 2026) —
//  replaces the placeholder that used to just be RecipeListView on the
//  first tab. Every section is independently collapsible: if it has
//  nothing to show, it disappears rather than rendering empty, per the
//  spec's own rule.
//
//  Scope notes, stated plainly:
//  - MFB (Memphis Family Barrentine) doesn't have its own hardcoded
//    section — instead, any public FamilyGroup with approvalPolicy ==
//    .noApprovalNeeded (MFB or otherwise) surfaces generically in
//    "Featured cookbooks," which itself is omitted, same as any other
//    empty section, until one exists.
//  - "Recently Added" is scoped to the user's own local recipes for now,
//    not merged with Firestore Publications from joined groups — a real
//    cross-store merge is more than this pass's scope.
//  - "Needs Your Attention" reuses the same GroupsServicing fetches
//    MessagesView already established, rendered as a horizontal strip
//    instead of a vertical list.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct HomeView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Environment(CookingSessionState.self) private var cookingSessionState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]
    @Query private var allCartItems: [CartItem]
    @Query private var allSections: [CookbookSection]

    @State private var adminPendingJoinRequests: [(request: JoinRequest, group: FamilyGroup)] = []
    @State private var pendingInvitations: [(invitation: Invitation, group: FamilyGroup)] = []
    @State private var incomingFriendRequests: [FriendRequest] = []
    @State private var outgoingFriendRequests: [FriendRequest] = []
    @State private var busyFriendRequestIDs: Set<String> = []
    @State private var friendRequestErrorMessage: String?
    /// "Decline" on an invitation card only enters this local soft state
    /// (Join/Decline disabled, Reconsider/Delete shown) — see
    /// InvitationCardState's header for why the real backend decline is
    /// deferred to Delete instead of firing here.
    @State private var softDeclinedInvitationIDs: Set<String> = []
    /// Permanently hidden — "mfb" for the placeholder, or a real
    /// Invitation's id once Delete has committed its backend decline.
    @State private var deletedInvitationIDs: Set<String> = []
    @State private var invitationActionErrorMessage: String?
    @State private var joinedGroups: [(membership: Membership, group: FamilyGroup, cookbook: GroupCookbook)] = []
    @State private var featuredGroups: [FamilyGroup] = []
    @State private var busyFeaturedGroupIDs: Set<String> = []
    @State private var featuredGroupErrorMessage: String?
    @State private var isPresentingMessages = false
    @State private var isPresentingAccount = false
    @State private var isPresentingCart = false
    @State private var isPresentingClearCartConfirmation = false
    @State private var cartErrorMessage: String?
    @State private var cloudSummaries: [PersonalCookbookSummary] = []
    @State private var busyCloudCookbookID: UUID?
    @State private var cloudSyncErrorMessage: String?
    @State private var isPresentingNewCookbook = false
    @State private var isPresentingNewRecipe = false
    @State private var isPresentingRestoreImporter = false
    @State private var isPresentingCloudRestore = false
    @State private var isPresentingRestoreChoice = false
    @State private var isPresentingFileImport = false
    @State private var isPresentingCommunitySearch = false
    @State private var isPresentingGettingStartedVideo = false
    @State private var entitlement: Entitlement?

    /// Synthetic id for the MFB placeholder — it has no real Invitation
    /// record to key InvitationCardState off of.
    private static let mfbInvitationID = "mfb"

    /// Flip this to true once Community Cookbooks (join requests, real
    /// invitations) actually launches. Until then Messages has nothing
    /// real to ever mark "active" — the MFB placeholder never counts,
    /// per hasActivePendingInvitation's own doc comment — so the
    /// hasActivePendingInvitation-driven position (top when something
    /// needs a decision, bottom otherwise) would always resolve to
    /// "bottom." Messages stays pinned right under Getting Started
    /// instead while that's true; once flipped, it reverts to the real
    /// position logic below.
    private let communityCookbooksAreLive = false

    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let friendsService: FriendsServicing = FirestoreFriendsService()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()
    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    private let syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService()
    private let photoUploadService: PersonalCookbookPhotoUploadServicing = FirebasePersonalCookbookPhotoUploadService()
    @State private var gate = EntitlementGateCoordinator()

    private var ownedRecipes: [Recipe] {
        allRecipes.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var ownedCartItems: [CartItem] {
        allCartItems.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var attentionCount: Int {
        adminPendingJoinRequests.count + activeInvitations.count + incomingFriendRequests.count + outgoingFriendRequests.count
    }

    /// Real invitations not yet soft-declined or deleted.
    private var activeInvitations: [(invitation: Invitation, group: FamilyGroup)] {
        pendingInvitations.filter {
            !softDeclinedInvitationIDs.contains($0.invitation.id) && !deletedInvitationIDs.contains($0.invitation.id)
        }
    }

    /// The MFB placeholder is permanent (no delete/decline lifecycle —
    /// see mfbInvitationPlaceholderCard), so Messages always has
    /// something to show; this is kept as its own flag anyway so a
    /// future "MFB actually launches" change has one obvious place to
    /// update the always-true assumption.
    private var hasAnyMessagesContent: Bool { true }

    /// Drives Messages' position in the dashboard — normal (near the top)
    /// while there's a *real* invitation actually awaiting a decision,
    /// bottom of the page once every real invitation has been
    /// soft-declined (or there are none). MFB never counts here — its
    /// buttons are permanently disabled, so it never represents
    /// something the user actually needs to act on. Join requests
    /// awaiting admin review don't affect this either — only invitations do.
    private var hasActivePendingInvitation: Bool {
        !activeInvitations.isEmpty
    }

    private var favoriteRecipes: [Recipe] {
        ownedRecipes.filter(\.isFavorite)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting

                    continueCookingCard

                    gettingStartedCard

                    annualMembershipWarningBanner

                    annualMembershipWontRenewBadge

                    if hasAnyMessagesContent && (!communityCookbooksAreLive || hasActivePendingInvitation) {
                        messagesStrip
                    }

                    if !ownedCookbooks.isEmpty || !joinedGroups.isEmpty {
                        yourCookbooksShelf
                    }

                    if !cloudSummaries.isEmpty {
                        cloudSyncStrip
                    }

                    if !featuredGroups.isEmpty {
                        featuredCookbooksShelf
                    }

                    favoriteDishesStrip

                    shoppingCartCard

                    if !ownedRecipes.isEmpty {
                        recentlyAddedStrip
                    }

                    if communityCookbooksAreLive && hasAnyMessagesContent && !hasActivePendingInvitation {
                        messagesStrip
                    }
                }
                .padding(.vertical)
            }
            .potluckHubBackground()
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Our Community Cookbook")
                        .font(.potluckHeadline(18))
                        .foregroundStyle(Color.potluckDeepTeal)
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 16) {
                        Button {
                            isPresentingMessages = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                if attentionCount > 0 {
                                    Text("\(attentionCount)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.white)
                                        .padding(4)
                                        .background(Circle().fill(Color.potluckTomato))
                                        .offset(x: 8, y: -8)
                                }
                            }
                        }
                        .accessibilityLabel(attentionCount > 0 ? "Messages, \(attentionCount) need your attention" : "Messages")

                        Button {
                            isPresentingAccount = true
                        } label: {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(Color.potluckTomato)
                        }
                        .accessibilityLabel("Profile")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { cookbookID in
                RecipeListView()
                    .onAppear { activeCookbookState.setActive(cookbookID) }
            }
            .sheet(isPresented: $isPresentingMessages) {
                MessagesView()
            }
            .sheet(isPresented: $isPresentingAccount) {
                AccountView()
            }
            .sheet(isPresented: $isPresentingCart) {
                ShoppingCartView()
            }
            .confirmationDialog(
                "Clear \(ownedCartItems.count) item\(ownedCartItems.count == 1 ? "" : "s") from your cart?",
                isPresented: $isPresentingClearCartConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    do {
                        try CartItemStore.clearAll(ownerID: accountState.currentOwnerID, in: modelContext)
                    } catch {
                        cartErrorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't Clear Cart", isPresented: Binding(
                get: { cartErrorMessage != nil },
                set: { if !$0 { cartErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cartErrorMessage ?? "")
            }
            .alert("Couldn't Sync", isPresented: Binding(
                get: { cloudSyncErrorMessage != nil },
                set: { if !$0 { cloudSyncErrorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(cloudSyncErrorMessage ?? "")
            }
            .task(id: accountState.currentUserID) {
                loadInvitationCardState()
                await loadGroupData()
                await loadCloudSummaries()
                await loadEntitlement()
            }
            .refreshable {
                await loadGroupData()
                await loadCloudSummaries()
                await loadEntitlement()
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

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(greetingText)
                .font(.potluckHeadline(26))
                .foregroundStyle(Color.potluckDeepTeal)
            Text("Here's what's cooking in your kitchens today.")
                .font(.potluckBody(15))
                .foregroundStyle(Color.potluckDeepTeal.opacity(0.65))
        }
        .padding(.horizontal)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let timeOfDay: String
        switch hour {
        case 0..<12: timeOfDay = "morning"
        case 12..<17: timeOfDay = "afternoon"
        default: timeOfDay = "evening"
        }
        if let firstName {
            return "Good \(timeOfDay), \(firstName)!"
        }
        return "Good \(timeOfDay)!"
    }

    private var firstName: String? {
        guard let displayName = accountState.currentUserDisplayName else { return nil }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.split(separator: " ").first.map(String.init)
    }

    // MARK: - Continue Cooking

    @ViewBuilder
    private var continueCookingCard: some View {
        // The recipe must actually resolve before the card is shown at
        // all — CookingSessionState persists across launches, so a
        // session can outlive the recipe it points to (deleted, or
        // recreated with a new id via reimport). Building a NavigationLink
        // whose destination closure can fail to produce a recipe used to
        // push to a genuinely blank screen; now a stale session just
        // falls through to "Jump Back In" instead.
        if let session = cookingSessionState.current,
           session.ownerID == accountState.currentOwnerID,
           let sessionRecipe = ownedRecipes.first(where: { $0.id == session.recipeID }) {
            NavigationLink {
                CookingModeView(recipe: sessionRecipe)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CONTINUE COOKING")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.potluckSunflower)
                    Text(session.recipeTitle)
                        .font(.potluckHeadline(22))
                        .foregroundStyle(.white)
                    Text("Step \(session.currentStepIndex + 1) of \(session.totalSteps)")
                        .font(.potluckBody(14))
                        .foregroundStyle(.white.opacity(0.85))
                    Text("Resume cooking →")
                        .font(.potluckSemiboldBody(15))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.white.opacity(0.2)))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(continueCookingBackground(sessionRecipe))
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        } else if let recent = ownedRecipes.first {
            NavigationLink {
                RecipeDetailView(recipe: recent)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("JUMP BACK IN")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.potluckSunflower)
                        Text(recent.title)
                            .font(.potluckHeadline(18))
                            .foregroundStyle(Color.potluckDeepTeal)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
                .padding(.horizontal)
            }
            .buttonStyle(.plain)
        }
    }

    /// The recipe's own photo as the card's full background when it has
    /// one, darkened enough for the white text stacked on top of it to
    /// stay legible — falls back to the flat teal the card always used.
    @ViewBuilder
    private func continueCookingBackground(_ recipe: Recipe) -> some View {
        ZStack {
            #if os(iOS)
            if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            } else {
                Color.potluckDeepTeal
            }
            #else
            Color.potluckDeepTeal
            #endif
            Color.black.opacity(0.45)
        }
    }

    // MARK: - Getting Started

    /// A standing dashboard fixture (not a one-time onboarding sheet) —
    /// stays visible even once the account has cookbooks, since its
    /// first row keeps being useful ("Add a New Recipe") long after
    /// "Create My First Cookbook" stops applying. Same dashed-border/
    /// message-plus-button shape as the MFB card in Messages, coral
    /// instead of sage so the two read as distinct sections at a glance —
    /// not four giant colored bars, which read as alarms/errors rather
    /// than an inviting list of things to try.
    private var gettingStartedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Getting Started", badge: nil)
            VStack(alignment: .leading, spacing: 16) {
                gettingStartedRow(
                    message: ownedCookbooks.isEmpty
                        ? "Start your very first cookbook, then add recipes to it."
                        : "Add another recipe to one of your cookbooks.",
                    buttonTitle: ownedCookbooks.isEmpty ? "Create My First Cookbook" : "Add a New Recipe"
                ) {
                    if let firstCookbook = ownedCookbooks.first {
                        if activeCookbookState.activeCookbookID == nil {
                            activeCookbookState.setActive(firstCookbook.id)
                        }
                        isPresentingNewRecipe = true
                    } else {
                        isPresentingNewCookbook = true
                    }
                }

                gettingStartedRow(
                    message: "Bring a cookbook back from a backup file, the cloud, or import recipes from a file.",
                    buttonTitle: "Restore a Cookbook"
                ) {
                    isPresentingRestoreChoice = true
                }

                gettingStartedRow(
                    message: "Search for a public Family Cookbook and join it.",
                    buttonTitle: "Connect to a Community Cookbook"
                ) {
                    isPresentingCommunitySearch = true
                }

                gettingStartedRow(
                    message: "A quick walkthrough of the basics.",
                    buttonTitle: "Watch a Getting Started Tutorial"
                ) {
                    isPresentingGettingStartedVideo = true
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius)
                    .strokeBorder(Color.potluckTomato, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            .potluckCardShadow()
            .padding(.horizontal)
        }
        .sheet(isPresented: $isPresentingNewCookbook) {
            CookbookConfigurationView(mode: .create(ownerID: accountState.currentOwnerID))
        }
        .sheet(isPresented: $isPresentingNewRecipe) {
            CreateEditRecipeView(mode: .create)
        }
        .sheet(isPresented: $isPresentingCloudRestore) {
            RestoreFromCloudView { cookbookID in
                activeCookbookState.setActive(cookbookID)
            }
        }
        .sheet(isPresented: $isPresentingCommunitySearch) {
            PublicGroupSearchView(groupsService: groupsService)
        }
        .sheet(isPresented: $isPresentingFileImport) {
            ImportRecipesFileView()
        }
        .fullScreenCover(isPresented: $isPresentingGettingStartedVideo) {
            GettingStartedTutorialPlayerView()
        }
        // .fileImporter itself is unavailable on tvOS — no user-facing
        // document/file system there — so "Restore from a Backup File"
        // isn't offered on this platform; "From the Cloud" (Firestore) is
        // unaffected and still works.
        #if !os(tvOS)
        .fileImporter(
            isPresented: $isPresentingRestoreImporter,
            allowedContentTypes: [.json]
        ) { result in
            switch result {
            case .success(let url):
                restoreFromBackupFile(url)
            case .failure(let error):
                cloudSyncErrorMessage = error.localizedDescription
            }
        }
        #endif
        .confirmationDialog("Restore from Where?", isPresented: $isPresentingRestoreChoice, titleVisibility: .visible) {
            #if !os(tvOS)
            Button("From a Backup File") { isPresentingRestoreImporter = true }
            #endif
            Button("From the Cloud") { isPresentingCloudRestore = true }
            Button("Import from a File") { isPresentingFileImport = true }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// A first cookbook being restored can never collide with an existing
    /// one — Getting Started only offers this button while ownedCookbooks
    /// is empty — so this skips CookbooksHubView's own overwrite-vs-add-new
    /// confirmation entirely and always restores as new.
    private func restoreFromBackupFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            cloudSyncErrorMessage = "Couldn't access that file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let data = try Data(contentsOf: url)
            let (cookbookID, _, _) = try CookbookBackupService.restore(data, ownerID: accountState.currentOwnerID, modelContext: modelContext)
            if let cookbookID {
                activeCookbookState.setActive(cookbookID)
            }
        } catch {
            cloudSyncErrorMessage = error.localizedDescription
        }
    }

    /// One row per Getting Started option — a short message plus a
    /// normal (not full-width) button, the same "descriptive text next
    /// to a modest action" shape the MFB/invitation cards already use,
    /// rather than a solid block of color that reads as an alert.
    private func gettingStartedRow(message: String, buttonTitle: String, isComingSoon: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if isComingSoon {
                messagesPillBadge("COMING SOON")
            }
            // Same font/weight/color as the Messages card's title text
            // (invitationCard/mfbInvitationPlaceholderCard) — this used to
            // be a lighter, dimmed style; matched up to Messages per
            // 2026-08-15 feedback.
            Text(message)
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(Color.potluckDeepTeal)
                .fixedSize(horizontal: false, vertical: true)
            Button(buttonTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color.potluckDenimBlue)
                .disabled(isComingSoon)
        }
    }

    // MARK: - Messages

    /// Always visible (unlike the shelves above it) — a standing MFB
    /// invitation placeholder lives here for every user, so there's
    /// always at least one card even with zero real join requests/invites.
    private var messagesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Messages", badge: attentionCount)

            // Every new user gets an MFB invitation by default — entirely
            // static/disabled, since the real join flow doesn't exist yet
            // (no Join, no Decline, no reconsider/delete lifecycle — that
            // lifecycle only makes sense once there's a real action
            // behind at least one of the buttons). Full-width, not part
            // of the horizontal strip below, since it's a standing
            // fixture, not one of a scrollable set of equal-weight items.
            mfbInvitationPlaceholderCard

            ForEach(activeCardInvitations, id: \.invitation.id) { entry in
                invitationCard(
                    id: entry.invitation.id,
                    title: "You've been invited to \(entry.group.name)",
                    onJoin: { Task { await respondToInvitation(entry.invitation, accept: true) } },
                    invitation: entry.invitation
                )
            }

            if !adminPendingJoinRequests.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(adminPendingJoinRequests, id: \.request.id) { entry in
                            attentionCard(
                                kind: "Join Request",
                                title: "Someone wants to join \(entry.group.name)",
                                primaryTitle: "Review"
                            ) {
                                isPresentingMessages = true
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            ForEach(incomingFriendRequests) { request in
                friendRequestCard(
                    badge: "FRIEND REQUEST",
                    title: "Friend request from Member \(request.senderID.suffix(6))"
                ) {
                    HStack {
                        Button("Accept") {
                            Task { await respondToFriendRequest(request, accept: true) }
                        }
                        Button("Decline", role: .destructive) {
                            Task { await respondToFriendRequest(request, accept: false) }
                        }
                    }
                    .disabled(busyFriendRequestIDs.contains(request.id))
                }
            }

            ForEach(outgoingFriendRequests) { request in
                friendRequestCard(
                    badge: "FRIEND REQUEST SENT",
                    title: "Friend request sent to Member \(request.recipientID.suffix(6))"
                ) {
                    Button("Cancel", role: .destructive) {
                        Task { await cancelFriendRequest(request) }
                    }
                    .disabled(busyFriendRequestIDs.contains(request.id))
                }
            }
        }
        .alert("Couldn't Update Invitation", isPresented: Binding(
            get: { invitationActionErrorMessage != nil },
            set: { if !$0 { invitationActionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(invitationActionErrorMessage ?? "")
        }
        .alert("Couldn't Update Friend Request", isPresented: Binding(
            get: { friendRequestErrorMessage != nil },
            set: { if !$0 { friendRequestErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(friendRequestErrorMessage ?? "")
        }
    }

    /// Same visual language as invitationCard, no soft-decline lifecycle
    /// — a friend request just quietly disappears on accept/decline/
    /// cancel, no reconsider step (unlike invitations, which is a
    /// deliberately richer flow not asked for here).
    private func friendRequestCard(badge: String, title: String, @ViewBuilder actions: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            messagesPillBadge(badge)
            Text(title)
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(Color.potluckDeepTeal)
                .fixedSize(horizontal: false, vertical: true)
            actions()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    /// Real invitations not yet permanently deleted — soft-declined ones
    /// still render (with Reconsider/Delete), only a real Delete removes
    /// the card.
    private var activeCardInvitations: [(invitation: Invitation, group: FamilyGroup)] {
        pendingInvitations.filter { !deletedInvitationIDs.contains($0.invitation.id) }
    }

    private func attentionCard(kind: String, title: String, primaryTitle: String, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(kind.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.potluckSage)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.potluckSage.opacity(0.15)))
            Text(title)
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(Color.potluckDeepTeal)
                .fixedSize(horizontal: false, vertical: true)
            Button(primaryTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(Color.potluckTomato)
        }
        .padding()
        .frame(width: 220, alignment: .leading)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
    }

    /// Shared by the MFB placeholder and every real invitation. Pending:
    /// Join (disabled for MFB, since the real join flow doesn't exist
    /// yet) + Decline, which only enters the soft-declined state below —
    /// no backend call for a real invitation happens until Delete.
    /// Soft-declined: both disabled, replaced by Reconsider (undoes the
    /// soft state, no backend involvement) + Delete (commits the real
    /// decline for a real invitation, then permanently hides the card).
    private func invitationCard(id: String, title: String, onJoin: (() -> Void)?, invitation: Invitation?) -> some View {
        let isSoftDeclined = softDeclinedInvitationIDs.contains(id)
        return VStack(alignment: .leading, spacing: 10) {
            messagesPillBadge("INVITATION")
            Text(title)
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(Color.potluckDeepTeal)
                .fixedSize(horizontal: false, vertical: true)

            if isSoftDeclined {
                HStack {
                    Button("Reconsider") {
                        reconsiderInvitation(id)
                    }
                    Button("Delete", role: .destructive) {
                        Task { await deleteInvitation(id: id, invitation: invitation) }
                    }
                }
            } else {
                HStack {
                    Button("Join") { onJoin?() }
                        .disabled(onJoin == nil)
                    Button("Decline", role: .destructive) {
                        declineInvitation(id)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isSoftDeclined ? "\(title). Declined. Reconsider or delete." : title)
    }

    /// Buttons are disabled (not omitted) and the card gets a dashed green
    /// border — both read as "placeholder, not yet active" on their own —
    /// since the real MFB join flow doesn't exist yet (no seeded MFB
    /// group, no auto-invitation system). Unlike a real invitation, there
    /// is no reconsider/delete lifecycle here — nothing behind either
    /// button is real yet, so there's nothing for that state machine to
    /// attach to.
    private var mfbInvitationPlaceholderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                messagesPillBadge("INVITATION")
                messagesPillBadge("COMING SOON")
            }
            Text("Join the Memphis Family Barrentine shared recipe & cookbook for free with over 600 southern classics!")
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(Color.potluckDeepTeal)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("Join") {}
                    .disabled(true)
                Button("Decline", role: .destructive) {}
                    .disabled(true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius)
                .strokeBorder(Color.potluckSage, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
        .potluckCardShadow()
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Invitation, coming soon. Join the Memphis Family Barrentine shared recipe and cookbook for free with over 600 southern classics. Join and Decline are not yet available.")
    }

    private func loadInvitationCardState() {
        let ownerID = accountState.currentOwnerID
        softDeclinedInvitationIDs = InvitationCardState.softDeclinedIDs(ownerID: ownerID)
        deletedInvitationIDs = InvitationCardState.deletedIDs(ownerID: ownerID)
    }

    private func declineInvitation(_ id: String) {
        let ownerID = accountState.currentOwnerID
        InvitationCardState.setSoftDeclined(id, ownerID: ownerID)
        softDeclinedInvitationIDs.insert(id)
    }

    private func reconsiderInvitation(_ id: String) {
        let ownerID = accountState.currentOwnerID
        InvitationCardState.clearSoftDeclined(id, ownerID: ownerID)
        softDeclinedInvitationIDs.remove(id)
    }

    /// For a real invitation, this is the moment the backend actually
    /// learns about the decline — if that call fails, the card is left
    /// exactly as it was (still soft-declined) rather than being hidden
    /// on a decline that never actually went through.
    private func deleteInvitation(id: String, invitation: Invitation?) async {
        let ownerID = accountState.currentOwnerID
        if let invitation, let userID = accountState.currentUserID {
            do {
                try await groupsService.respondToInvitation(invitation.id, accept: false, respondingUserID: userID)
            } catch {
                invitationActionErrorMessage = error.localizedDescription
                return
            }
            pendingInvitations.removeAll { $0.invitation.id == id }
        }
        InvitationCardState.setDeleted(id, ownerID: ownerID)
        deletedInvitationIDs.insert(id)
        softDeclinedInvitationIDs.remove(id)
    }

    private func respondToInvitation(_ invitation: Invitation, accept: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        do {
            try await groupsService.respondToInvitation(invitation.id, accept: accept, respondingUserID: userID)
            pendingInvitations.removeAll { $0.invitation.id == invitation.id }
            await loadGroupData()
        } catch {
            invitationActionErrorMessage = error.localizedDescription
        }
    }

    private func respondToFriendRequest(_ request: FriendRequest, accept: Bool) async {
        guard let userID = accountState.currentUserID else { return }
        busyFriendRequestIDs.insert(request.id)
        defer { busyFriendRequestIDs.remove(request.id) }
        do {
            try await friendsService.respondToFriendRequest(request.id, accept: accept, respondingUserID: userID)
            incomingFriendRequests.removeAll { $0.id == request.id }
        } catch {
            friendRequestErrorMessage = error.localizedDescription
        }
    }

    private func cancelFriendRequest(_ request: FriendRequest) async {
        guard let userID = accountState.currentUserID else { return }
        busyFriendRequestIDs.insert(request.id)
        defer { busyFriendRequestIDs.remove(request.id) }
        do {
            try await friendsService.cancelFriendRequest(request.id, actingUserID: userID)
            outgoingFriendRequests.removeAll { $0.id == request.id }
        } catch {
            friendRequestErrorMessage = error.localizedDescription
        }
    }

    private func messagesPillBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.potluckSage)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.potluckSage.opacity(0.15)))
    }

    // MARK: - Your Cookbooks

    private var yourCookbooksShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Your Cookbooks", badge: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ownedCookbooks) { cookbook in
                        // Value-based link, not a destination-builder
                        // NavigationLink with a .simultaneousGesture layered
                        // on — that combination breaks full-row/cover
                        // tappability (see CookbooksHubView). The active
                        // cookbook is set in .navigationDestination below.
                        NavigationLink(value: cookbook.id) {
                            cookbookCover(
                                title: cookbook.title,
                                subtitle: "\(ownedRecipes.filter { $0.cookbookID == cookbook.id }.count) recipes"
                            ) {
                                ownedCookbookCoverImage(cookbook)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(joinedGroups, id: \.cookbook.id) { entry in
                        NavigationLink {
                            GroupCookbookView(group: entry.group, cookbook: entry.cookbook, membership: entry.membership, groupsService: groupsService)
                        } label: {
                            cookbookCover(
                                title: entry.cookbook.cookbookName,
                                subtitle: "\(entry.group.name)"
                            ) {
                                joinedGroupCoverImage(entry.group)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // MARK: - Cloud Sync

    /// Two severities: a calmer notice starting at day 75 past
    /// annualProMembershipExpiresAt, an urgent one from day 85 — both
    /// still well before the 90-day photo-deletion sweep, so there's a
    /// real window to act. Absent entirely once the member has renewed or
    /// never subscribed at all (daysPastAnnualMembershipExpiration is nil).
    @ViewBuilder
    private var annualMembershipWarningBanner: some View {
        if let daysPast = daysPastAnnualMembershipExpiration, daysPast >= 75, let expiresAt = entitlement?.annualProMembershipExpiresAt {
            let isUrgent = daysPast >= 85
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isUrgent ? "exclamationmark.triangle.fill" : "clock.badge.exclamationmark")
                    .foregroundStyle(isUrgent ? .red : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(isUrgent ? "Your Cloud Photos Will Be Removed Soon" : "Your Pro Membership Expired")
                        .font(.potluckSemiboldBody(15))
                    Text("Your Annual Pro Membership expired on \(expiresAt.formatted(date: .abbreviated, time: .omitted)). Renew within 90 days of that date to keep your cloud-synced photos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Renew Membership") {
                        isPresentingAccount = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
            .padding(.horizontal)
        }
    }

    /// Quiet, non-urgent — the membership is still active, this is purely
    /// informational so a member who turned off auto-renew isn't caught
    /// off guard weeks later with no earlier signal (annualProMembershipWillRenew,
    /// last known from an appStoreServerNotifications DID_CHANGE_RENEWAL_STATUS).
    @ViewBuilder
    private var annualMembershipWontRenewBadge: some View {
        if entitlement?.isActiveAnnualProMember == true,
           entitlement?.annualProMembershipWillRenew == false,
           let expiresAt = entitlement?.annualProMembershipExpiresAt {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(.secondary)
                Text("Your Annual Pro Membership won't renew — active through \(expiresAt.formatted(date: .abbreviated, time: .omitted)).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
        }
    }

    /// One card per cookbook this account has ever synced to the cloud
    /// (FirestorePersonalCookbookSyncService.fetchSyncedCookbooks), not
    /// just ones already on this device — the whole point is surfacing a
    /// cookbook that was synced from another device but never pulled down
    /// here, which RootTabView's one-shot "Cookbooks Available" alert used
    /// to be the only way to discover (and only once, ever, per cookbook
    /// id — see DismissedCloudCookbookPrompts). This stays visible and
    /// re-checks every launch/pull-to-refresh instead.
    private var cloudSyncStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Cloud Sync", badge: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(cloudSummaries) { summary in
                        cloudSyncCard(summary)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// Shares its cover (image/style/color, via ownedCookbookCoverImage)
    /// with the identical cookbook's card in yourCookbooksShelf once it's
    /// loaded locally — a plain white card here read as "a second,
    /// different cookbook" sitting right next to its own real cover in
    /// Your Cookbooks, rather than the sync status of that same one.
    private func cloudSyncCard(_ summary: PersonalCookbookSummary) -> some View {
        let localCookbook = ownedCookbooks.first { $0.id == summary.id }
        let isBusy = busyCloudCookbookID == summary.id

        return VStack(alignment: .leading, spacing: 4) {
            Spacer()
            Text(localCookbook == nil ? "AVAILABLE IN THE CLOUD" : "SYNCED")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
            Text(summary.title)
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(.white)
                .lineLimit(2)
            if let localCookbook {
                Text(lastSyncedCaption(for: localCookbook))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            } else {
                Text("Updated \(summary.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if isBusy {
                ProgressView()
                    .tint(.white)
            } else if let localCookbook {
                Button("Sync Now") {
                    Task { await syncNow(localCookbook) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.potluckTomato)
                .controlSize(.small)
            } else {
                Button("Load") {
                    Task { await loadFromCloud(summary) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(Color.potluckTomato)
                .controlSize(.small)
            }
        }
        .padding()
        .frame(width: 160, height: 160, alignment: .leading)
        .background {
            ZStack {
                if let localCookbook {
                    ownedCookbookCoverImage(localCookbook)
                } else {
                    Color.potluckDeepTeal
                }
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.35),
                        .init(color: .black.opacity(0.5), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
    }

    private func lastSyncedCaption(for cookbook: Cookbook) -> String {
        guard let lastSyncedAt = cookbook.lastSyncedAt else { return "Never synced" }
        return "Synced \(lastSyncedAt.formatted(.relative(presentation: .named)))"
    }

    private func loadCloudSummaries() async {
        guard let userID = accountState.currentUserID else {
            cloudSummaries = []
            return
        }
        cloudSummaries = (try? await syncService.fetchSyncedCookbooks(forUser: userID)) ?? []
    }

    private func loadEntitlement() async {
        guard let userID = accountState.currentUserID else {
            entitlement = nil
            return
        }
        entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
    }

    /// Days past annualProMembershipExpiresAt — nil while still active or
    /// never activated. Computed client-side from the same date the sweep
    /// itself reads; the two warning touchpoints (day 75/85) are purely a
    /// display threshold here, independent of the sweep's own
    /// once-per-lapse email dedup markers.
    private var daysPastAnnualMembershipExpiration: Int? {
        guard let expiresAt = entitlement?.annualProMembershipExpiresAt, expiresAt < .now else { return nil }
        return Calendar.current.dateComponents([.day], from: expiresAt, to: .now).day
    }

    private func loadFromCloud(_ summary: PersonalCookbookSummary) async {
        guard let ownerUserID = accountState.currentUserID else { return }
        busyCloudCookbookID = summary.id
        defer { busyCloudCookbookID = nil }
        do {
            _ = try await PersonalCookbookSyncCoordinator.pull(
                cookbookID: summary.id, ownerUserID: ownerUserID,
                modelContext: modelContext, syncService: syncService
            )
        } catch {
            cloudSyncErrorMessage = error.localizedDescription
        }
    }

    private func syncNow(_ cookbook: Cookbook) async {
        guard let ownerUserID = accountState.currentUserID else { return }
        busyCloudCookbookID = cookbook.id
        defer { busyCloudCookbookID = nil }
        let recipesInCookbook = ownedRecipes.filter { $0.cookbookID == cookbook.id }
        do {
            try await PersonalCookbookSyncCoordinator.push(
                cookbook, recipes: recipesInCookbook, ownerUserID: ownerUserID,
                syncService: syncService, photoUploadService: photoUploadService,
                isActiveProMember: entitlement?.isEffectivelyProUser ?? false
            )
            try? modelContext.save()
            await loadCloudSummaries()
        } catch {
            cloudSyncErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Featured Cookbooks

    /// Public cookbooks the user hasn't joined that let anyone in
    /// instantly (FamilyGroup.approvalPolicy == .noApprovalNeeded) — a small,
    /// deliberately open set, not a general "browse all public
    /// cookbooks" surface (that's PublicGroupSearchView). Tapping Join
    /// grants membership right away since these opted into that.
    private var featuredCookbooksShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Featured Cookbooks", badge: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuredGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Spacer()
                            Text(group.name)
                                .font(.potluckSemiboldBody(15))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(group.locationText)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.85))
                            Button("Join") {
                                Task { await joinFeatured(group) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.white)
                            .foregroundStyle(Color.potluckSage)
                            .controlSize(.small)
                            .disabled(busyFeaturedGroupIDs.contains(group.id))
                        }
                        .padding()
                        .frame(width: 160, height: 140, alignment: .leading)
                        .background(Color.potluckSage)
                        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                        .potluckCardShadow()
                    }
                }
                .padding(.horizontal)
            }

            if let featuredGroupErrorMessage {
                Text(featuredGroupErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private func joinFeatured(_ group: FamilyGroup) async {
        guard let userID = accountState.currentUserID else { return }
        busyFeaturedGroupIDs.insert(group.id)
        featuredGroupErrorMessage = nil
        defer { busyFeaturedGroupIDs.remove(group.id) }

        let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
        await gate.attempt(.groupJoin, outcome: EntitlementGate.forGroupJoin(entitlement, group: group)) {
            do {
                _ = try await groupsService.requestToJoin(groupID: group.id, requesterID: userID, note: nil)
                await loadGroupData()
            } catch {
                featuredGroupErrorMessage = error.localizedDescription
            }
        }
    }

    private func cookbookCover<Cover: View>(title: String, subtitle: String, @ViewBuilder cover: () -> Cover) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
            Text(title)
                .font(.potluckSemiboldBody(15))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding()
        .frame(width: 140, height: 120, alignment: .leading)
        .background {
            ZStack {
                cover()
                // A bottom-anchored gradient, not a flat scrim — the title/
                // subtitle text sits at the bottom of the card, so only
                // that band needs darkening for legibility. A flat overlay
                // across the whole card made a user's own cover photo read
                // as dim/tinted even though nothing was wrong with it.
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.45),
                        .init(color: .black.opacity(0.33), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
    }

    @ViewBuilder
    /// Priority: a custom cover image always wins; otherwise a chosen
    /// Cover Style; otherwise the plain color — matches CookbookConfigurationView's
    /// own documented priority order.
    private func ownedCookbookCoverImage(_ cookbook: Cookbook) -> some View {
        #if os(iOS)
        if let filename = cookbook.coverImageFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityHidden(true)
        } else if let style = CookbookCoverStyleCatalog.style(named: cookbook.coverStyleImageName) {
            Image(style.imageAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .accessibilityHidden(true)
        } else {
            Color(hex: cookbook.coverColorHex)
        }
        #else
        if let style = CookbookCoverStyleCatalog.style(named: cookbook.coverStyleImageName) {
            Image(style.imageAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color(hex: cookbook.coverColorHex)
        }
        #endif
    }

    /// FamilyGroup.coverImageURL has no upload path anywhere in the app
    /// yet, so this is always nil today — matching GroupCookbookView's
    /// own header, which already handles it the same way, so the shelf
    /// picks it up automatically whenever that changes.
    @ViewBuilder
    private func joinedGroupCoverImage(_ group: FamilyGroup) -> some View {
        if let urlString = group.coverImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.potluckSage
            }
        } else {
            Color.potluckSage
        }
    }

    // MARK: - Shopping Cart

    private var shoppingCartCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Shopping Cart", badge: nil)

            if ownedCartItems.isEmpty {
                emptyStateCard("Items you add to your shopping list will show here.", isTransparent: true)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(cartPreviewText)
                        .font(.potluckBody(14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    HStack {
                        Button("View cart") {
                            isPresentingCart = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.potluckTomato)

                        Button("Clear all", role: .destructive) {
                            isPresentingClearCartConfirmation = true
                        }
                        .font(.subheadline)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
                .padding(.horizontal)
            }
        }
    }

    private var cartPreviewText: String {
        let names = ownedCartItems.prefix(4).map(\.displayText)
        let suffix = ownedCartItems.count > 4 ? " + \(ownedCartItems.count - 4) more" : ""
        return names.joined(separator: ", ") + suffix
    }

    /// Shared by every section that's now always-visible instead of
    /// collapsing away when it has nothing to show — Favorite Dishes and
    /// Shopping Cart both use this for their empty state. isTransparent
    /// only applies to Shopping Cart's call site (per 2026-08-15
    /// feedback, matching the section-icon placeholder's own
    /// transparency) — Favorite Dishes keeps its opaque card via the
    /// default.
    private func emptyStateCard(_ message: String, isTransparent: Bool = false) -> some View {
        Text(message)
            .font(.potluckBody(14))
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(isTransparent ? 0.3 : 1))
            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
            .potluckCardShadow()
            .padding(.horizontal)
    }

    // MARK: - Favorite Dishes

    private var favoriteDishesStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Favorite Dishes", badge: nil)

            if favoriteRecipes.isEmpty {
                emptyStateCard("Your favorite recipes will show here.")
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(favoriteRecipes.prefix(10)) { recipe in
                            NavigationLink {
                                RecipeDetailView(recipe: recipe)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    recentlyAddedThumbnail(recipe)
                                    Text(recipe.title)
                                        .font(.potluckSemiboldBody(14))
                                        .foregroundStyle(Color.potluckDeepTeal)
                                        .lineLimit(1)
                                }
                                .frame(width: 140, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Recently Added

    private var recentlyAddedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recently Added", badge: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ownedRecipes.prefix(10)) { recipe in
                        NavigationLink {
                            RecipeDetailView(recipe: recipe)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                recentlyAddedThumbnail(recipe)
                                Text(recipe.title)
                                    .font(.potluckSemiboldBody(14))
                                    .foregroundStyle(Color.potluckDeepTeal)
                                    .lineLimit(1)
                                Text(creditLabel(for: recipe))
                                    .font(.caption)
                                    .foregroundStyle(Color.potluckSage)
                                    .lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    /// "Yours" only when nothing else is claiming credit — ownerID (who
    /// can edit, always the local account for anything in ownedRecipes)
    /// is deliberately not what this reflects. An inspirationCredit counts
    /// as "other credit" even for a self-entered recipe; authorLineage
    /// only overrides "Yours" when it's external (a Discover download or
    /// a paste-import's own "By:" line) — a self-attributed authorLineage
    /// is just the owner crediting themself, which is what "Yours" already
    /// says. The two are mutually exclusive by construction (CreateEditRecipeView
    /// only offers inspirationCredit when authorLineageIsExternal is false).
    private func creditLabel(for recipe: Recipe) -> String {
        if let inspirationCredit = recipe.inspirationCredit, !inspirationCredit.isEmpty {
            return inspirationCredit
        }
        if recipe.authorLineageIsExternal, let authorLineage = recipe.authorLineage, !authorLineage.isEmpty {
            return authorLineage
        }
        return "Yours"
    }

    /// The dish's own photo when it has one, at the same size/shape the
    /// placeholder always used (140×100, PotluckMetrics.cardCornerRadius)
    /// — falls back to that same placeholder otherwise, same pattern
    /// RecipeRow's thumbnail already uses in RecipeListView.
    @ViewBuilder
    private func recentlyAddedThumbnail(_ recipe: Recipe) -> some View {
        #if os(iOS)
        if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 100)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .accessibilityHidden(true)
        } else {
            recentlyAddedPlaceholder(recipe)
        }
        #else
        recentlyAddedPlaceholder(recipe)
        #endif
    }

    private func sectionIcon(for recipe: Recipe) -> CookbookSectionIcon? {
        guard let sectionID = recipe.sectionID,
              let section = allSections.first(where: { $0.id == sectionID }) else { return nil }
        return CookbookSectionIconCatalog.icon(named: section.iconAssetName)
    }

    @ViewBuilder
    private func recentlyAddedPlaceholder(_ recipe: Recipe) -> some View {
        if let sectionIcon = sectionIcon(for: recipe) {
            RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius)
                .fill(Color.potluckSunflower.opacity(0.3))
                .frame(width: 140, height: 100)
                .overlay {
                    Image(sectionIcon.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                }
        } else {
            RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius)
                .fill(Color.potluckSunflower.opacity(0.3))
                .frame(width: 140, height: 100)
                .overlay {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Color.potluckTomato)
                }
        }
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String, badge: Int?) -> some View {
        HStack {
            Text(title)
                .font(.potluckHeadline(18))
                .foregroundStyle(Color.potluckDeepTeal)
            if let badge, badge > 0 {
                Text("\(badge)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Circle().fill(Color.potluckTomato))
            }
        }
        .padding(.horizontal)
    }

    private func loadGroupData() async {
        guard let userID = accountState.currentUserID else {
            adminPendingJoinRequests = []
            pendingInvitations = []
            joinedGroups = []
            featuredGroups = []
            incomingFriendRequests = []
            outgoingFriendRequests = []
            return
        }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var groups: [(Membership, FamilyGroup)] = []
            var cookbookEntries: [(Membership, FamilyGroup, GroupCookbook)] = []
            var pendingRequests: [(JoinRequest, FamilyGroup)] = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                groups.append((membership, group))
                let cookbooks = try await groupsService.fetchGroupCookbooks(forGroup: membership.groupID)
                cookbookEntries.append(contentsOf: cookbooks.map { (membership, group, $0) })
                if membership.role == .admin {
                    let pending = try await groupsService.fetchJoinRequests(forGroup: membership.groupID)
                    pendingRequests.append(contentsOf: pending.map { ($0, group) })
                }
            }
            joinedGroups = cookbookEntries
            adminPendingJoinRequests = pendingRequests

            if let email = accountState.currentUserEmail {
                let invitations = try await groupsService.fetchInvitations(forInvitee: email)
                var invitationEntries: [(Invitation, FamilyGroup)] = []
                for invitation in invitations {
                    if let group = try await groupsService.fetchGroup(id: invitation.groupID) {
                        invitationEntries.append((invitation, group))
                    }
                }
                pendingInvitations = invitationEntries
            } else {
                pendingInvitations = []
            }

            let joinedIDs = Set(groups.map { $0.1.id })
            let publicGroups = try await groupsService.fetchPublicGroups(matching: PublicGroupSearchFilter(text: nil, locationText: nil))
            featuredGroups = publicGroups.filter { $0.approvalPolicy == .noApprovalNeeded && !joinedIDs.contains($0.id) }

            incomingFriendRequests = try await friendsService.fetchFriendRequests(forRecipient: userID)
            outgoingFriendRequests = try await friendsService.fetchFriendRequests(bySender: userID)
        } catch {
            // Home degrades gracefully — sections requiring this data
            // just don't render rather than showing an error banner.
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
        .environment(CookingSessionState())
}
