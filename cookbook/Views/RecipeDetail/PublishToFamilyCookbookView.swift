//
//  PublishToFamilyCookbookView.swift
//  cookbook
//
//  Publishing the same recipe to the same group again updates the
//  existing Publication in place (PublicationsServicing's own doc comment,
//  LIN-001) — so this view always says "Publish," never worries about
//  create-vs-update, and a photo upload failure never blocks the text
//  content from publishing (RecipePhotoUploadServicing is best-effort).
//

import SwiftUI

struct PublishToFamilyCookbookView: View {
    let recipe: Recipe
    let groupsService: GroupsServicing
    let publicationsService: PublicationsServicing
    let photoUploadService: RecipePhotoUploadServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss

    @State private var eligibleGroups: [FamilyGroup] = []
    @State private var publishedGroupIDs: Set<String> = []
    @State private var isLoading = false
    @State private var busyGroupIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if eligibleGroups.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Family Cookbooks to Publish To",
                        systemImage: "person.3",
                        description: Text("Join or create a Family Cookbook first, or ask an admin to allow member publishing.")
                    )
                } else {
                    ForEach(eligibleGroups) { group in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.cookbookName)
                                    .font(.headline)
                                Text("\(group.name) · \(group.locationText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(publishedGroupIDs.contains(group.id) ? "Republish" : "Publish") {
                                Task { await publish(to: group) }
                            }
                            .disabled(busyGroupIDs.contains(group.id))
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let statusMessage {
                    Text(statusMessage).foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Publish to a Family Cookbook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await loadEligibleGroups()
            }
        }
    }

    private func loadEligibleGroups() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var groups: [FamilyGroup] = []
            var published: Set<String> = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                guard membership.role == .admin || group.allowsMemberPublishing else { continue }
                groups.append(group)

                let existing = try await publicationsService.fetchPublications(forGroup: group.id)
                if existing.contains(where: { $0.sourceRecipeID == recipe.id.uuidString && $0.ownerUserID == userID }) {
                    published.insert(group.id)
                }
            }
            eligibleGroups = groups
            publishedGroupIDs = published
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publish(to group: FamilyGroup) async {
        guard let userID = accountState.currentUserID else { return }
        busyGroupIDs.insert(group.id)
        errorMessage = nil
        statusMessage = nil
        defer { busyGroupIDs.remove(group.id) }

        var coverImageURL: String?
        if let filename = recipe.heroPhotoFilename, let imageData = PhotoStore.data(for: filename) {
            // Best-effort: a photo upload hiccup shouldn't block publishing
            // the recipe's text content.
            coverImageURL = try? await photoUploadService.upload(
                imageData: imageData,
                groupID: group.id,
                ownerUserID: userID,
                sourceRecipeID: recipe.id.uuidString
            ).absoluteString
        }

        let content = PublicationContentSnapshot.make(from: recipe, coverImageURL: coverImageURL)

        do {
            _ = try await publicationsService.publish(content, sourceRecipeID: recipe.id.uuidString, to: group.id, ownerUserID: userID)
            publishedGroupIDs.insert(group.id)
            statusMessage = "Published to \(group.cookbookName)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let recipe = Recipe(ownerID: "preview", title: "Skillet Cornbread")
    return PublishToFamilyCookbookView(
        recipe: recipe,
        groupsService: InMemoryGroupsService(),
        publicationsService: InMemoryPublicationsService(),
        photoUploadService: FakeRecipePhotoUploadService()
    )
    .environment(AccountState(authService: FakeAuthService()))
}
