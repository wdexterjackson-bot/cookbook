//
//  CommunityCookbookRecipesView.swift
//  cookbook
//
//  The Cookbooks tab's destination for a Community Cookbook — mirrors
//  RecipeListView's personal-cookbook shape (header, recipe list, "No
//  Recipes Yet" empty state) rather than the old combined info/manage
//  screen (see CommunityCookbookManageView, reached instead from
//  Administrator > Manage Community Cookbooks). A brand-new, still-empty
//  cookbook offers an "Import Recipes from Existing Cookbook" action
//  (reusing PublishCookbookToFamilyCookbookView's bulk-publish machinery,
//  pre-locked to this cookbook as the destination) — it disappears the
//  moment the cookbook actually has recipes in it, same one-time-only
//  framing as the empty-state affordance it sits alongside.
//

import SwiftUI
import SwiftData

struct CommunityCookbookRecipesView: View {
    let group: FamilyGroup
    let cookbook: GroupCookbook
    let membership: Membership
    let groupsService: GroupsServicing

    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query private var allCookbooks: [Cookbook]
    @State private var publications: [Publication] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyPublicationIDs: Set<String> = []
    @State private var isPresentingImport = false
    /// Which publications the current user has liked — loaded once
    /// alongside the publications themselves, then kept in sync locally as
    /// the user taps Like (PublicationsServicing.setLiked is the source of
    /// truth; this is just this screen's own read of it).
    @State private var likedPublicationIDs: Set<String> = []
    @State private var busyLikePublicationIDs: Set<String> = []
    /// This user's own rating per publication, if any — same load-once,
    /// keep-in-sync-locally shape as likedPublicationIDs above.
    @State private var myRatings: [String: Int] = [:]
    @State private var busyRatingPublicationIDs: Set<String> = []
    @State private var busyCopyPublicationIDs: Set<String> = []
    @State private var copyStatusMessage: String?

    private let publicationsService: PublicationsServicing = FirestorePublicationsService()
    private let photoUploadService: RecipePhotoUploadServicing = FirebaseRecipePhotoUploadService()

    /// Same eligibility rule PublishCookbookToFamilyCookbookView and
    /// PublishToFamilyCookbookView already use elsewhere — an admin can
    /// always import, a plain member only when this cookbook explicitly
    /// allows member publishing.
    private var canImport: Bool {
        membership.role == .admin || cookbook.allowsMemberPublishing
    }

    var body: some View {
        // No NavigationStack here — always pushed as a destination from
        // CookbooksHubView, same convention RecipeListView documents for
        // itself.
        VStack(spacing: 0) {
            cookbookHeader
            recipeListOrEmptyState
        }
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadPublications()
        }
        .sheet(isPresented: $isPresentingImport) {
            PublishCookbookToFamilyCookbookView(fixedDestination: (group: group, cookbook: cookbook))
        }
        .onChange(of: isPresentingImport) { wasPresenting, isPresenting in
            // The import sheet publishes recipes as a side effect — refresh
            // once it's dismissed so the (now non-empty) list replaces the
            // empty state without the user needing to pull-to-refresh.
            if wasPresenting, !isPresenting {
                Task { await loadPublications() }
            }
        }
    }

    @ViewBuilder
    private var recipeListOrEmptyState: some View {
        Group {
            if publications.isEmpty && !isLoading {
                ContentUnavailableView {
                    Label("No Recipes Yet", systemImage: "fork.knife")
                } description: {
                    Text("No recipes have been published to \(cookbook.cookbookName) yet.")
                } actions: {
                    if canImport {
                        Button("Import Recipes from Existing Cookbook") {
                            isPresentingImport = true
                        }
                    }
                }
            } else {
                ScrollViewReader { scrollProxy in
                    List {
                        ForEach(publications) { publication in
                            publicationRow(publication)
                        }
                        if let errorMessage {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                        if let copyStatusMessage {
                            Text(copyStatusMessage).foregroundStyle(Color.potluckSage)
                        }
                    }
                    .potluckHiddenScrollBackground()
                    #if os(iOS)
                    .overlay(alignment: .trailing) {
                        ScrollScrubber(itemIDs: publications.map(\.id), proxy: scrollProxy)
                    }
                    #endif
                }
            }
        }
    }

    private var cookbookHeader: some View {
        VStack(spacing: 8) {
            Text(cookbook.cookbookName)
                .font(.potluckHeadline(24))
                .foregroundStyle(Color.potluckDeepTeal)
                .multilineTextAlignment(.center)

            coverArt
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    /// Priority: a custom uploaded image wins; otherwise a chosen Cover
    /// Style; otherwise the plain color — same fallback order
    /// RecipeListView's personal-cookbook header uses.
    @ViewBuilder
    private var coverArt: some View {
        if let urlString = cookbook.coverImageURL ?? group.coverImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
        } else if let styleName = cookbook.coverStyleImageName, let style = CookbookCoverStyleCatalog.style(named: styleName) {
            Image(style.imageAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color(hex: cookbook.coverColorHex ?? Cookbook.defaultColorHex)
        }
    }

    @ViewBuilder
    private func publicationRow(_ publication: Publication) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let urlString = publication.content.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(publication.content.title)
                    .font(.headline)
                if !publication.content.summary.isEmpty {
                    Text(publication.content.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                likeRow(publication)
                ratingRow(publication)

                // The cookbook-wide ceiling (cookbook.commentsAllowed) hides
                // this entry point even if a recipe's own commentsEnabled
                // flag is stale-true from before an admin turned the
                // ceiling off — see CommunityCookbookManageView's Cookbook
                // Settings section.
                if publication.commentsEnabled && (cookbook.commentsAllowed ?? true) {
                    NavigationLink {
                        PublicationCommentsView(publication: publication, membership: membership, publicationsService: publicationsService)
                    } label: {
                        Label("Comments", systemImage: "bubble.left")
                    }
                    .font(.caption)
                }

                Button {
                    copyToPersonal(publication)
                } label: {
                    Label("Copy to Personal", systemImage: "square.and.arrow.down")
                }
                .font(.caption)
                .disabled(busyCopyPublicationIDs.contains(publication.id) || targetCookbook == nil)

                if publication.ownerUserID == accountState.currentUserID {
                    Button("Unpublish", role: .destructive) {
                        Task { await unpublish(publication) }
                    }
                    .font(.caption)
                    .disabled(busyPublicationIDs.contains(publication.id))
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// Whichever of the copier's own cookbooks is currently active
    /// (ActiveCookbookState — same source CreateEditRecipeView defaults
    /// to), falling back to their first cookbook if none is active yet.
    /// No cookbook-picker UI here on purpose — matches the plan's scope
    /// decision to reuse existing resolution rather than build new UI.
    private var targetCookbook: Cookbook? {
        let owned = allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
        return owned.first { $0.id == activeCookbookState.activeCookbookID } ?? owned.first
    }

    private func copyToPersonal(_ publication: Publication) {
        guard let userID = accountState.currentUserID, let cookbook = targetCookbook else { return }
        busyCopyPublicationIDs.insert(publication.id)
        errorMessage = nil
        defer { busyCopyPublicationIDs.remove(publication.id) }
        switch RecipeCopyCoordinator.copy(publication, forUserID: userID, into: cookbook, modelContext: modelContext) {
        case .success:
            copyStatusMessage = "Added \"\(publication.content.title)\" to \(cookbook.title)."
        case .failure(let error):
            errorMessage = "Couldn't copy this recipe: \(error.localizedDescription)"
        }
    }

    /// Shared-cookbook-only counterpart to RecipeDetailView's Love button —
    /// a personal recipe has no group of other members to aggregate a
    /// count across, so Like only exists here, never on a personal recipe.
    @ViewBuilder
    private func likeRow(_ publication: Publication) -> some View {
        let isLiked = likedPublicationIDs.contains(publication.id)
        Button {
            Task { await toggleLike(publication) }
        } label: {
            Label("\(publication.likeCount ?? 0)", systemImage: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup")
                .font(.caption)
                .foregroundStyle(isLiked ? Color.potluckTomato : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(busyLikePublicationIDs.contains(publication.id))
        .accessibilityLabel(isLiked ? "Unlike" : "Like")
        .accessibilityValue("\(publication.likeCount ?? 0) likes")
    }

    /// Shared-cookbook-only, same as likeRow above — a 1-5 star rating
    /// with the group's average, plus a Clear affordance since a user
    /// might want to remove their rating entirely, not just change it.
    @ViewBuilder
    private func ratingRow(_ publication: Publication) -> some View {
        let myRating = myRatings[publication.id]
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    Task { await applyRating(publication, rating: star) }
                } label: {
                    Image(systemName: star <= (myRating ?? 0) ? "star.fill" : "star")
                        .foregroundStyle(star <= (myRating ?? 0) ? Color.potluckSunflower : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Rate \(star) star\(star == 1 ? "" : "s")")
            }
            Text(averageRatingText(for: publication))
                .font(.caption)
                .foregroundStyle(.secondary)
            if myRating != nil {
                Button("Clear") {
                    Task { await removeRating(publication) }
                }
                .font(.caption)
            }
        }
        .disabled(busyRatingPublicationIDs.contains(publication.id))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(myRating.map { "Your rating: \($0) of 5 stars" } ?? "Not yet rated")
    }

    private func averageRatingText(for publication: Publication) -> String {
        guard let count = publication.ratingCount, count > 0, let sum = publication.ratingSum else {
            return "No ratings yet"
        }
        let average = Double(sum) / Double(count)
        return "\(average.formatted(.number.precision(.fractionLength(1)))) (\(count))"
    }

    private func applyRating(_ publication: Publication, rating: Int) async {
        guard let userID = accountState.currentUserID else { return }
        guard let index = publications.firstIndex(where: { $0.id == publication.id }) else { return }
        busyRatingPublicationIDs.insert(publication.id)
        defer { busyRatingPublicationIDs.remove(publication.id) }
        do {
            let (sum, count) = try await publicationsService.setRating(publication.id, userID: userID, rating: rating)
            publications[index].ratingSum = sum
            publications[index].ratingCount = count
            myRatings[publication.id] = rating
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeRating(_ publication: Publication) async {
        guard let userID = accountState.currentUserID else { return }
        guard let index = publications.firstIndex(where: { $0.id == publication.id }) else { return }
        busyRatingPublicationIDs.insert(publication.id)
        defer { busyRatingPublicationIDs.remove(publication.id) }
        do {
            let (sum, count) = try await publicationsService.clearRating(publication.id, userID: userID)
            publications[index].ratingSum = sum
            publications[index].ratingCount = count
            myRatings[publication.id] = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleLike(_ publication: Publication) async {
        guard let userID = accountState.currentUserID else { return }
        guard let index = publications.firstIndex(where: { $0.id == publication.id }) else { return }
        let wasLiked = likedPublicationIDs.contains(publication.id)
        busyLikePublicationIDs.insert(publication.id)
        defer { busyLikePublicationIDs.remove(publication.id) }
        do {
            let newCount = try await publicationsService.setLiked(publication.id, userID: userID, liked: !wasLiked)
            publications[index].likeCount = newCount
            if wasLiked {
                likedPublicationIDs.remove(publication.id)
            } else {
                likedPublicationIDs.insert(publication.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func unpublish(_ publication: Publication) async {
        guard let userID = accountState.currentUserID else { return }
        busyPublicationIDs.insert(publication.id)
        errorMessage = nil
        defer { busyPublicationIDs.remove(publication.id) }
        do {
            try await publicationsService.unpublish(publication.id, actingUserID: userID)
            // Best-effort — an orphaned Storage file is a minor cost, not
            // worth blocking the unpublish the user actually asked for.
            try? await photoUploadService.delete(groupID: group.id, cookbookID: cookbook.id, ownerUserID: userID, sourceRecipeID: publication.sourceRecipeID)
            await loadPublications()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadPublications() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // A group can hold several cookbooks now — scope down to just
            // this one client-side, since fetchPublications(forGroup:)
            // doesn't take a cookbook filter.
            publications = try await publicationsService.fetchPublications(forGroup: group.id)
                .filter { $0.cookbookID == cookbook.id }
            if let userID = accountState.currentUserID {
                var liked: Set<String> = []
                for publication in publications where try await publicationsService.hasLiked(publication.id, userID: userID) {
                    liked.insert(publication.id)
                }
                likedPublicationIDs = liked

                var ratings: [String: Int] = [:]
                for publication in publications {
                    if let rating = try await publicationsService.myRating(publication.id, userID: userID) {
                        ratings[publication.id] = rating
                    }
                }
                myRatings = ratings
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
