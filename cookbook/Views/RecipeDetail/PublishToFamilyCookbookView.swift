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

    @State private var eligibleCookbooks: [(group: FamilyGroup, cookbook: GroupCookbook)] = []
    @State private var publishedCookbookIDs: Set<String> = []
    @State private var isLoading = false
    @State private var busyCookbookIDs: Set<String> = []
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var allowComments = false

    var body: some View {
        NavigationStack {
            List {
                if eligibleCookbooks.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Family Cookbooks to Publish To",
                        systemImage: "person.3",
                        description: Text("Join or create a Family Cookbook first, or ask an admin to allow member publishing.")
                    )
                } else {
                    Section {
                        Toggle("Allow Comments?", isOn: $allowComments)
                    } footer: {
                        Text("Lets other members comment on this recipe once published. Applies to every cookbook you publish to below.")
                    }

                    ForEach(eligibleCookbooks, id: \.cookbook.id) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.cookbook.cookbookName)
                                    .font(.headline)
                                Text("\(entry.group.name) · \(entry.group.locationText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(publishedCookbookIDs.contains(entry.cookbook.id) ? "Republish" : "Publish") {
                                Task { await publish(entry) }
                            }
                            .disabled(busyCookbookIDs.contains(entry.cookbook.id))
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
            .potluckHiddenScrollBackground()
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
                await loadEligibleCookbooks()
            }
        }
    }

    private func loadEligibleCookbooks() async {
        guard let userID = accountState.currentUserID else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var eligible: [(FamilyGroup, GroupCookbook)] = []
            var published: Set<String> = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                let cookbooks = try await groupsService.fetchGroupCookbooks(forGroup: membership.groupID)
                let existing = try await publicationsService.fetchPublications(forGroup: group.id)
                // Scoped per cookbook, not just per group — a group can
                // hold several cookbooks now, and publishing to one
                // shouldn't show as "already published" against another.
                for cookbook in cookbooks where membership.role == .admin || cookbook.allowsMemberPublishing {
                    eligible.append((group, cookbook))
                    let alreadyPublishedHere = existing.contains {
                        $0.cookbookID == cookbook.id && $0.sourceRecipeID == recipe.id.uuidString && $0.ownerUserID == userID
                    }
                    if alreadyPublishedHere {
                        published.insert(cookbook.id)
                    }
                }
            }
            eligibleCookbooks = eligible
            publishedCookbookIDs = published
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publish(_ entry: (group: FamilyGroup, cookbook: GroupCookbook)) async {
        guard let userID = accountState.currentUserID else { return }
        busyCookbookIDs.insert(entry.cookbook.id)
        errorMessage = nil
        statusMessage = nil
        defer { busyCookbookIDs.remove(entry.cookbook.id) }

        do {
            let photoUploadSucceeded = try await RecipePublishingCoordinator.publish(
                recipe, to: entry.group, cookbook: entry.cookbook, ownerUserID: userID, commentsEnabled: allowComments,
                publicationsService: publicationsService, photoUploadService: photoUploadService
            )
            publishedCookbookIDs.insert(entry.cookbook.id)
            statusMessage = photoUploadSucceeded
                ? "Published to \(entry.cookbook.cookbookName)."
                : "Published to \(entry.cookbook.cookbookName), but the photo couldn't be uploaded."
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
