//
//  PublishCookbookToFamilyCookbookView.swift
//  cookbook
//
//  Administrator screen's bulk publish action — publishes every recipe
//  in a chosen personal cookbook to a chosen Family Cookbook in one pass,
//  reusing RecipePublishingCoordinator (the same publish logic Recipe
//  Detail's one-at-a-time flow uses) per recipe. Built for the "hundreds
//  of already-imported recipes need to become a shared cookbook" case,
//  where publishing one at a time from Recipe Detail isn't realistic.
//  One failing recipe doesn't stop the rest, same principle as bulk file
//  import — the results screen lists anything that couldn't publish.
//

import SwiftUI
import SwiftData

struct PublishCookbookToFamilyCookbookView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    @Query private var allCookbooks: [Cookbook]
    @Query private var allRecipes: [Recipe]

    @State private var selectedCookbookID: UUID?
    @State private var eligibleCookbooks: [(group: FamilyGroup, cookbook: GroupCookbook)] = []
    @State private var selectedGroupCookbookID: String?
    @State private var isLoadingGroups = false
    @State private var isPublishing = false
    @State private var publishedCount = 0
    @State private var failedTitles: [String] = []
    @State private var titlesWithFailedPhotos: [String] = []
    @State private var isComplete = false
    @State private var errorMessage: String?

    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let publicationsService: PublicationsServicing = FirestorePublicationsService()
    private let photoUploadService: RecipePhotoUploadServicing = FirebaseRecipePhotoUploadService()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var recipesInSelectedCookbook: [Recipe] {
        guard let selectedCookbookID else { return [] }
        return allRecipes.filter { $0.ownerID == accountState.currentOwnerID && $0.cookbookID == selectedCookbookID }
    }

    var body: some View {
        NavigationStack {
            Form {
                if isComplete {
                    Section("Results") {
                        Text("\(publishedCount) recipe\(publishedCount == 1 ? "" : "s") published. You may close this window now.")
                        if !failedTitles.isEmpty {
                            Text("\(failedTitles.count) couldn't be published:")
                                .foregroundStyle(.secondary)
                            ForEach(failedTitles, id: \.self) { title in
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !titlesWithFailedPhotos.isEmpty {
                            Text("\(titlesWithFailedPhotos.count) published without their photo (upload failed):")
                                .foregroundStyle(.secondary)
                            ForEach(titlesWithFailedPhotos, id: \.self) { title in
                                Text(title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else {
                    Section("Source") {
                        Picker("Cookbook", selection: $selectedCookbookID) {
                            Text("Choose a Cookbook").tag(UUID?.none)
                            ForEach(ownedCookbooks) { cookbook in
                                Text(cookbook.title).tag(UUID?.some(cookbook.id))
                            }
                        }
                        if selectedCookbookID != nil {
                            Text("\(recipesInSelectedCookbook.count) recipe\(recipesInSelectedCookbook.count == 1 ? "" : "s") will be published.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section {
                        if isLoadingGroups {
                            ProgressView()
                        } else if eligibleCookbooks.isEmpty {
                            Text("No Community Cookbooks you can publish to yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Community Cookbook", selection: $selectedGroupCookbookID) {
                                Text("Choose a Community Cookbook").tag(String?.none)
                                ForEach(eligibleCookbooks, id: \.cookbook.id) { entry in
                                    Text(entry.cookbook.cookbookName).tag(String?.some(entry.cookbook.id))
                                }
                            }
                        }
                    } header: {
                        Text("Destination")
                    } footer: {
                        Text("Republishing a recipe already published to this cookbook updates it in place rather than duplicating it.")
                    }

                    if isPublishing {
                        Section {
                            HStack {
                                ProgressView()
                                Text("Publishing \(publishedCount + failedTitles.count) of \(recipesInSelectedCookbook.count)…")
                            }
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(.red)
                        }
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Publish a Cookbook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isComplete ? "Done" : "Cancel") { dismiss() }
                }
                if !isComplete {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Publish") {
                            Task { await publishAll() }
                        }
                        .disabled(selectedCookbookID == nil || selectedGroupCookbookID == nil || recipesInSelectedCookbook.isEmpty || isPublishing)
                    }
                }
            }
            .task {
                await loadEligibleCookbooks()
            }
        }
    }

    private func loadEligibleCookbooks() async {
        guard let userID = accountState.currentUserID else { return }
        isLoadingGroups = true
        errorMessage = nil
        defer { isLoadingGroups = false }
        do {
            let memberships = try await groupsService.fetchMemberships(forUser: userID).filter { $0.status == .active }
            var eligible: [(FamilyGroup, GroupCookbook)] = []
            for membership in memberships {
                guard let group = try await groupsService.fetchGroup(id: membership.groupID) else { continue }
                let cookbooks = try await groupsService.fetchGroupCookbooks(forGroup: membership.groupID)
                for cookbook in cookbooks where membership.role == .admin || cookbook.allowsMemberPublishing {
                    eligible.append((group, cookbook))
                }
            }
            eligibleCookbooks = eligible
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func publishAll() async {
        guard let userID = accountState.currentUserID,
              let selectedGroupCookbookID,
              let entry = eligibleCookbooks.first(where: { $0.cookbook.id == selectedGroupCookbookID }) else {
            return
        }
        let group = entry.group
        isPublishing = true
        errorMessage = nil
        publishedCount = 0
        failedTitles = []
        titlesWithFailedPhotos = []

        // Fetched once and reused for every recipe in this batch, not
        // per-recipe — the publisher's membership doesn't change mid-run.
        let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
        let isActiveAnnualProMember = entitlement?.isActiveAnnualProMember == true

        for recipe in recipesInSelectedCookbook {
            do {
                let photoUploadSucceeded = try await RecipePublishingCoordinator.publish(
                    recipe, to: group, cookbook: entry.cookbook, ownerUserID: userID,
                    isActiveAnnualProMember: isActiveAnnualProMember,
                    publicationsService: publicationsService, photoUploadService: photoUploadService
                )
                publishedCount += 1
                if !photoUploadSucceeded {
                    titlesWithFailedPhotos.append(recipe.title)
                }
            } catch {
                failedTitles.append(recipe.title)
            }
        }

        isPublishing = false
        isComplete = true
    }
}

#Preview {
    PublishCookbookToFamilyCookbookView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
