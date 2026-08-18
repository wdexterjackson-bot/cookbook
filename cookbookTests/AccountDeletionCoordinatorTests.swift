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

    private func makeGroupDetails(name: String) -> NewGroupDetails {
        NewGroupDetails(
            name: name,
            description: "",
            type: "Family",
            locationText: "Memphis, TN",
            structuredRegion: nil,
            visibility: .publicGroup,
            allowsMemberInvites: false,
            approvalPolicy: .anyAdministrator
        )
    }

    private func makeCookbookDetails(cookbookName: String) -> NewGroupCookbookDetails {
        NewGroupCookbookDetails(cookbookName: cookbookName, allowsMemberPublishing: true)
    }

    private func createTestGroup(
        _ groups: InMemoryGroupsService,
        name: String,
        cookbookName: String,
        idempotencyKey: String = "req-1"
    ) async throws -> FamilyGroup {
        let (group, _) = try await groups.createGroup(
            makeGroupDetails(name: name),
            cookbookDetails: makeCookbookDetails(cookbookName: cookbookName),
            creatorUserID: "alice",
            creatorDisplayName: "Alice",
            idempotencyKey: idempotencyKey
        )
        return group
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
        let group = try await createTestGroup(groups, name: "Barrentines", cookbookName: "Reunion")
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
        let group = try await createTestGroup(groups, name: "Barrentines", cookbookName: "Reunion")
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
        let group = try await createTestGroup(groups, name: "Solo", cookbookName: "Solo Cookbook")

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
        let group = try await createTestGroup(groups, name: "Barrentines", cookbookName: "Reunion")
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
        let published = try await publications.publish(content, sourceRecipeID: "r1", to: group.id, cookbookID: "cb-1", ownerUserID: "bob")

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

    /// A deleted user's own comment on someone *else's* publication should
    /// also read as tombstoned afterward, not just publications they
    /// owned — the display name changes, everything else (including the
    /// publication's own attribution, since alice isn't being deleted)
    /// stays untouched. Likes are deliberately left alone entirely.
    @Test func tombstonesTheDeletedUsersOwnCommentsOnOtherPeoplesPublications() async throws {
        let context = try makeInMemoryContext()
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let group = try await createTestGroup(groups, name: "Barrentines", cookbookName: "Reunion")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "alice")

        let publications = InMemoryPublicationsService()
        let content = PublicationContentSnapshot(
            title: "Alice's Cornbread",
            summary: "", yield: "", totalTimeMinutes: nil,
            ingredientSections: [], stepSections: [], notes: "", tags: []
        )
        let published = try await publications.publish(content, sourceRecipeID: "r1", to: group.id, cookbookID: "cb-1", ownerUserID: "alice")
        try await publications.setCommentsEnabled(published.id, enabled: true, actingUserID: "alice")
        _ = try await publications.addComment(published.id, authorUserID: "bob", authorDisplayName: "Bob", text: "This looks great!")
        _ = try await publications.setLiked(published.id, userID: "bob", liked: true)

        try await AccountDeletionCoordinator.deleteAllData(
            for: "bob",
            modelContext: context,
            groupsService: groups,
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService(),
            publicationsService: publications
        )

        let comments = try await publications.fetchComments(published.id)
        let comment = try #require(comments.first)
        #expect(comment.authorUserID == "bob")
        #expect(comment.authorDisplayName == "Deleted User")
        #expect(comment.text == "This looks great!")

        let survivingPublication = try #require(await publications.fetchPublication(id: published.id))
        #expect(survivingPublication.content.authorLineage == nil)
        #expect(survivingPublication.likeCount == 1)
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

    @Test func bestEffortCleansUpAllFriendDataSoNoGhostsAreLeftBehind() async throws {
        let context = try makeInMemoryContext()
        let friends = InMemoryFriendsService()
        // Alice has an outgoing request to carol, an incoming one from dave,
        // and an accepted friendship with bob — deleting alice should
        // resolve all three so nobody's left with a permanent ghost.
        _ = try await friends.sendFriendRequest(from: "alice", to: "carol")
        _ = try await friends.sendFriendRequest(from: "dave", to: "alice")
        let bobRequest = try await friends.sendFriendRequest(from: "alice", to: "bob")
        try await friends.respondToFriendRequest(bobRequest.id, accept: true, respondingUserID: "bob")

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: InMemoryGroupsService(),
            entitlementService: InMemoryEntitlementService(),
            userProfileService: InMemoryUserProfileService(),
            friendsService: friends
        )

        #expect(try await friends.fetchFriendRequests(forRecipient: "carol").isEmpty)
        #expect(try await friends.fetchFriendRequests(forRecipient: "alice").isEmpty)
        #expect(try await friends.fetchFriends(forUser: "alice").isEmpty)
        #expect(try await friends.fetchFriends(forUser: "bob").isEmpty)
    }
}
