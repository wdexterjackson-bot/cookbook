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
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var busyPublicationIDs: Set<String> = []

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
                    Task { await leave() }
                }
                if membership.role == .admin {
                    Button("Archive Cookbook", role: .destructive) {
                        Task { await archive() }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadPublications()
        }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leave() async {
        do {
            try await groupsService.leaveGroup(groupID: group.id, userID: membership.userID)
            dismiss()
        } catch GroupsServiceError.lastAdminCannotLeaveOrBeDemoted {
            errorMessage = "You're the last admin of this cookbook — promote someone else first."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Archiving (rather than leaving) is what actually resolves the
    /// "you're the sole admin" block — leaving alone would still strand
    /// the cookbook, which is exactly what leaveGroup refuses to allow.
    private func archive() async {
        do {
            try await groupsService.archiveGroup(groupID: group.id, actingUserID: membership.userID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
