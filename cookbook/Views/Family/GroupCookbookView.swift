//
//  GroupCookbookView.swift
//  cookbook
//
//  Read-only browse of a Family Cookbook's published recipes. Publishing a
//  personal recipe INTO a Family Cookbook is a deliberately deferred
//  follow-up (confirmed scope decision) — a brand-new cookbook shows an
//  honest empty state here rather than silently looking broken.
//

import SwiftUI

struct GroupCookbookView: View {
    let group: FamilyGroup
    let membership: Membership
    let groupsService: GroupsServicing

    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    @State private var publications: [Publication] = []
    @State private var groupMemberships: [Membership] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyPublicationIDs: Set<String> = []
    @State private var isPresentingLeaveConfirmation = false
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

    private let publicationsService: PublicationsServicing = FirestorePublicationsService()
    private let photoUploadService: RecipePhotoUploadServicing = FirebaseRecipePhotoUploadService()

    var body: some View {
        List {
            Section {
                cookbookHeader
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Family/Group", value: group.name)
                LabeledContent("Location", value: group.locationText)
                LabeledContent("Your Role", value: membership.role.rawValue.capitalized)
                LabeledContent("Visibility", value: group.visibility == .publicGroup ? "Public" : "Private")
            }

            Section("Recipes") {
                if publications.isEmpty && !isLoading {
                    Text("No recipes have been published to this cookbook yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(publications) { publication in
                        publicationRow(publication)
                    }
                }
            }

            Section {
                Button("Leave Family Cookbook", role: .destructive) {
                    isPresentingLeaveConfirmation = true
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadPublications()
            await loadMemberships()
        }
        .confirmationDialog(
            leaveConfirmationMessage,
            isPresented: $isPresentingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button(isLastActiveMember ? "Delete Cookbook" : "Leave", role: .destructive) {
                Task { await leave() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Whether `membership.userID` leaving would be the last active
    /// membership on this group — leaveGroup deletes the whole cookbook in
    /// that case rather than just marking this one membership `.left`.
    private var isLastActiveMember: Bool {
        GroupPolicy.isLastActiveMember(membership.userID, in: groupMemberships)
    }

    private var leaveConfirmationMessage: String {
        if isLastActiveMember {
            return "You're the last member of \(group.cookbookName). Leaving will permanently delete this cookbook and everything in it — recipes and photos — for everyone. This cannot be undone."
        }
        return "Leave \(group.name)? You'll be removed from this Family Cookbook."
    }

    private var cookbookHeader: some View {
        VStack(spacing: 8) {
            Text(group.cookbookName)
                .font(.potluckHeadline(24))
                .foregroundStyle(Color.potluckDeepTeal)
                .multilineTextAlignment(.center)

            if let urlString = group.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
            }
        }
        .padding(.vertical, 4)
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
            try? await photoUploadService.delete(groupID: group.id, ownerUserID: userID, sourceRecipeID: publication.sourceRecipeID)
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
            publications = try await publicationsService.fetchPublications(forGroup: group.id)
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

    private func loadMemberships() async {
        groupMemberships = (try? await groupsService.fetchMemberships(forGroup: group.id)) ?? []
    }

    private func leave() async {
        do {
            try await groupsService.leaveGroup(groupID: group.id, userID: membership.userID)
            dismiss()
        } catch GroupsServiceError.lastAdminCannotLeaveOrBeDemoted {
            errorMessage = "You're the last admin of this cookbook with other active members still in it — promote someone else first."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
