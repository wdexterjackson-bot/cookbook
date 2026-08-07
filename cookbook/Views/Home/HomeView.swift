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
//    section — instead, any public FamilyGroup with
//    autoApproveJoinRequests set (MFB or otherwise) surfaces generically
//    in "Featured cookbooks," which itself is omitted, same as any other
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

struct HomeView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Environment(CookingSessionState.self) private var cookingSessionState
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]
    @Query private var allCartItems: [CartItem]

    @State private var adminPendingJoinRequests: [(request: JoinRequest, group: FamilyGroup)] = []
    @State private var pendingInvitations: [(invitation: Invitation, group: FamilyGroup)] = []
    @State private var joinedGroups: [(membership: Membership, group: FamilyGroup)] = []
    @State private var featuredGroups: [FamilyGroup] = []
    @State private var busyFeaturedGroupIDs: Set<String> = []
    @State private var featuredGroupErrorMessage: String?
    @State private var isPresentingMessages = false
    @State private var isPresentingAccount = false
    @State private var isPresentingCart = false
    @State private var isPresentingClearCartConfirmation = false

    private let groupsService: GroupsServicing = FirestoreGroupsService()

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
        adminPendingJoinRequests.count + pendingInvitations.count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    greeting

                    continueCookingCard

                    if attentionCount > 0 {
                        needsAttentionStrip
                    }

                    if !ownedCookbooks.isEmpty || !joinedGroups.isEmpty {
                        yourCookbooksShelf
                    }

                    if !featuredGroups.isEmpty {
                        featuredCookbooksShelf
                    }

                    if !ownedCartItems.isEmpty {
                        shoppingCartCard
                    }

                    if !ownedRecipes.isEmpty {
                        recentlyAddedStrip
                    }
                }
                .padding(.vertical)
            }
            .background(Color.potluckCream)
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Family Recipe Book")
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
                    CartItemStore.clearAll(ownerID: accountState.currentOwnerID, in: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            }
            .task(id: accountState.currentUserID) {
                await loadGroupData()
            }
            .refreshable {
                await loadGroupData()
            }
        }
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
            } else {
                Color.potluckDeepTeal
            }
            #else
            Color.potluckDeepTeal
            #endif
            Color.black.opacity(0.45)
        }
    }

    // MARK: - Needs Your Attention

    private var needsAttentionStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Needs your attention", badge: attentionCount)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(adminPendingJoinRequests, id: \.request.id) { entry in
                        attentionCard(
                            kind: "Join Request",
                            title: "Someone wants to join \(entry.group.cookbookName)",
                            primaryTitle: "Review"
                        ) {
                            isPresentingMessages = true
                        }
                    }
                    ForEach(pendingInvitations, id: \.invitation.id) { entry in
                        attentionCard(
                            kind: "Invitation",
                            title: "You've been invited to \(entry.group.cookbookName)",
                            primaryTitle: "Review"
                        ) {
                            isPresentingMessages = true
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
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
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
    }

    // MARK: - Your Cookbooks

    private var yourCookbooksShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Your cookbooks", badge: nil)

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
                    ForEach(joinedGroups, id: \.group.id) { entry in
                        NavigationLink {
                            GroupCookbookView(group: entry.group, membership: entry.membership, groupsService: groupsService)
                        } label: {
                            cookbookCover(
                                title: entry.group.cookbookName,
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

    // MARK: - Featured Cookbooks

    /// Public cookbooks the user hasn't joined that let anyone in
    /// instantly (FamilyGroup.autoApproveJoinRequests) — a small,
    /// deliberately open set, not a general "browse all public
    /// cookbooks" surface (that's PublicGroupSearchView). Tapping Join
    /// grants membership right away since these opted into that.
    private var featuredCookbooksShelf: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Featured cookbooks", badge: nil)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(featuredGroups) { group in
                        VStack(alignment: .leading, spacing: 4) {
                            Spacer()
                            Text(group.cookbookName)
                                .font(.potluckSemiboldBody(15))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(group.name)
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
        do {
            _ = try await groupsService.requestToJoin(groupID: group.id, requesterID: userID, note: nil)
            await loadGroupData()
        } catch {
            featuredGroupErrorMessage = error.localizedDescription
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
                // A flat scrim, not a directional gradient — the title/
                // subtitle text sits at the bottom of the whole card, but
                // a cover image can be any photo, so a uniform darkening
                // keeps white text legible regardless of what's in it.
                Color.black.opacity(0.35)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
    }

    @ViewBuilder
    private func ownedCookbookCoverImage(_ cookbook: Cookbook) -> some View {
        #if os(iOS)
        if let filename = cookbook.coverImageFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color(hex: cookbook.coverColorHex)
        }
        #else
        Color(hex: cookbook.coverColorHex)
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
            sectionHeader("Shopping cart", badge: nil)

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
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
            .potluckCardShadow()
            .padding(.horizontal)
        }
    }

    private var cartPreviewText: String {
        let names = ownedCartItems.prefix(4).map(\.displayText)
        let suffix = ownedCartItems.count > 4 ? " + \(ownedCartItems.count - 4) more" : ""
        return names.joined(separator: ", ") + suffix
    }

    // MARK: - Recently Added

    private var recentlyAddedStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Recently added", badge: nil)

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
                                Text("Yours")
                                    .font(.caption)
                                    .foregroundStyle(Color.potluckSage)
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
        } else {
            recentlyAddedPlaceholder
        }
        #else
        recentlyAddedPlaceholder
        #endif
    }

    private var recentlyAddedPlaceholder: some View {
        RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius)
            .fill(Color.potluckSunflower.opacity(0.3))
            .frame(width: 140, height: 100)
            .overlay {
                Image(systemName: "fork.knife")
                    .foregroundStyle(Color.potluckTomato)
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
            return
        }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var groups: [(Membership, FamilyGroup)] = []
            var pendingRequests: [(JoinRequest, FamilyGroup)] = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                groups.append((membership, group))
                if membership.role == .admin {
                    let pending = try await groupsService.fetchJoinRequests(forGroup: membership.groupID)
                    pendingRequests.append(contentsOf: pending.map { ($0, group) })
                }
            }
            joinedGroups = groups
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
            featuredGroups = publicGroups.filter { $0.autoApproveJoinRequests && !joinedIDs.contains($0.id) }
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
