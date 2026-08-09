//
//  AccountDeletionCoordinatorTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct AccountDeletionCoordinatorTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeDetails(name: String, cookbookName: String) -> NewGroupDetails {
        NewGroupDetails(
            name: name,
            cookbookName: cookbookName,
            description: "",
            type: "Family",
            locationText: "Memphis, TN",
            structuredRegion: nil,
            visibility: .publicGroup,
            allowsMemberInvites: false,
            allowsMemberPublishing: true,
            autoApproveJoinRequests: false
        )
    }

    @Test func deletesAllLocalRecipesAndCookbooksForTheUser() async throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: "alice", title: "Cornbread")
        let cookbook = Cookbook(ownerID: "alice", title: "Personal Cookbook", sortOrder: 0)
        context.insert(recipe)
        context.insert(cookbook)
        try context.save()

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: InMemoryGroupsService(),
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService()
        )

        #expect(try context.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cookbook>()).isEmpty)
    }

    @Test func doesNotTouchAnotherUsersLocalData() async throws {
        let context = try makeInMemoryContext()
        let mine = Recipe(ownerID: "alice", title: "Mine")
        let theirs = Recipe(ownerID: "bob", title: "Not Mine")
        context.insert(mine)
        context.insert(theirs)
        try context.save()

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: InMemoryGroupsService(),
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService()
        )

        let remaining = try context.fetch(FetchDescriptor<Recipe>())
        #expect(remaining.map(\.title) == ["Not Mine"])
    }

    @Test func leavesNonBlockingGroupMemberships() async throws {
        let context = try makeInMemoryContext()
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Barrentines", cookbookName: "Reunion"), creatorUserID: "alice", idempotencyKey: "req-1")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "alice")

        try await AccountDeletionCoordinator.deleteAllData(
            for: "bob",
            modelContext: context,
            groupsService: groups,
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService()
        )

        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.first { $0.userID == "bob" }?.status == .left)
    }

    @Test func blocksWhenTheSoleAdminOfAMultiMemberCookbook() async throws {
        let context = try makeInMemoryContext()
        let recipe = Recipe(ownerID: "alice", title: "Should Survive")
        context.insert(recipe)
        try context.save()

        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Barrentines", cookbookName: "Reunion"), creatorUserID: "alice", idempotencyKey: "req-1")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "alice")

        await #expect(throws: AccountDeletionError.blockedByAdminOnlyCookbooks(cookbookNames: ["Reunion"])) {
            try await AccountDeletionCoordinator.deleteAllData(
                for: "alice",
                modelContext: context,
                groupsService: groups,
                entitlementService: InMemoryEntitlementService(),
                userProfileService: InMemoryUserProfileService()
            )
        }

        // Nothing should have been touched — blocked before any deletion.
        #expect(try context.fetch(FetchDescriptor<Recipe>()).count == 1)
        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.first { $0.userID == "alice" }?.status == .active)
    }

    /// A solo admin isn't blocked, unlike an admin who'd be stranding other
    /// active members — leaveGroup's last-active-member rule deletes the
    /// group entirely instead, so there's nothing left to strand.
    @Test func deletesTheGroupWhenTheSoleAdminIsTheOnlyMember() async throws {
        let context = try makeInMemoryContext()
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Solo", cookbookName: "Solo Cookbook"), creatorUserID: "alice", idempotencyKey: "req-1")

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: groups,
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService()
        )

        let remaining = try await groups.fetchGroup(id: group.id)
        #expect(remaining == nil)
    }

    @Test func bestEffortDeletesTheEntitlementDocument() async throws {
        let context = try makeInMemoryContext()
        let entitlements = InMemoryEntitlementService()
        entitlements.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", tier1Credits: 1, tier2Credits: 2, isProUser: false,
            receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
        )

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: InMemoryGroupsService(),
            entitlementService: entitlements,
            userProfileService: InMemoryUserProfileService()
        )

        #expect(entitlements.entitlementsByUserID["alice"] == nil)
    }

    /// PRD §6.6: a deleted account's identity is pseudonymized, but a
    /// publication they left behind in a group that survives them should
    /// stick around with a non-identifying tombstone rather than silently
    /// still crediting a since-deleted account by name forever.
    @Test func tombstonesPublicationsInGroupsThatSurviveTheDeletedOwner() async throws {
        let context = try makeInMemoryContext()
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Barrentines", cookbookName: "Reunion"), creatorUserID: "alice", idempotencyKey: "req-1")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "alice")

        let publications = InMemoryPublicationsService()
        let content = PublicationContentSnapshot(
            title: "Bob's Cornbread",
            summary: "",
            yield: "",
            totalTimeMinutes: nil,
            ingredientSections: [],
            stepSections: [],
            notes: "",
            tags: [],
            authorLineage: "Bob Barrentine of Memphis, TN"
        )
        let published = try await publications.publish(content, sourceRecipeID: "r1", to: group.id, ownerUserID: "bob")

        try await AccountDeletionCoordinator.deleteAllData(
            for: "bob",
            modelContext: context,
            groupsService: groups,
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService(),
            publicationsService: publications
        )

        let survivingPublication = try #require(await publications.fetchPublication(id: published.id))
        #expect(survivingPublication.content.authorLineage == "Original contributor deleted")
        #expect(survivingPublication.ownerUserID == "bob")
        #expect(survivingPublication.state == .published)
    }

    @Test func bestEffortDeletesTheProfileDocument() async throws {
        let context = try makeInMemoryContext()
        let userProfiles = InMemoryUserProfileService()
        userProfiles.locationsByUserID["alice"] = UserLocation(city: "Memphis", isUS: true, stateCode: "TN", country: nil)

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: InMemoryGroupsService(),
            entitlementService: InMemoryEntitlementService(),
            userProfileService: userProfiles
        )

        #expect(userProfiles.locationsByUserID["alice"] == nil)
    }
}
