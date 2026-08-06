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
            allowsMemberPublishing: true
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
            entitlementService: InMemoryEntitlementService()
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
            entitlementService: InMemoryEntitlementService()
        )

        let remaining = try context.fetch(FetchDescriptor<Recipe>())
        #expect(remaining.map(\.title) == ["Not Mine"])
    }

    @Test func leavesNonBlockingGroupMemberships() async throws {
        let context = try makeInMemoryContext()
        let groups = InMemoryGroupsService()
        groups.creditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Barrentines", cookbookName: "Reunion"), creatorUserID: "alice", idempotencyKey: "req-1")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "alice")

        try await AccountDeletionCoordinator.deleteAllData(
            for: "bob",
            modelContext: context,
            groupsService: groups,
            entitlementService: InMemoryEntitlementService()
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
        groups.creditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Barrentines", cookbookName: "Reunion"), creatorUserID: "alice", idempotencyKey: "req-1")
        let joinRequest = try await groups.requestToJoin(groupID: group.id, requesterID: "bob", note: nil)
        try await groups.decideJoinRequest(joinRequest.id, approve: true, decidedByUserID: "alice")

        await #expect(throws: AccountDeletionError.blockedByAdminOnlyCookbooks(cookbookNames: ["Reunion"])) {
            try await AccountDeletionCoordinator.deleteAllData(
                for: "alice",
                modelContext: context,
                groupsService: groups,
                entitlementService: InMemoryEntitlementService()
            )
        }

        // Nothing should have been touched — blocked before any deletion.
        #expect(try context.fetch(FetchDescriptor<Recipe>()).count == 1)
        let memberships = try await groups.fetchMemberships(forGroup: group.id)
        #expect(memberships.first { $0.userID == "alice" }?.status == .active)
    }

    /// GroupPolicy.isLastActiveAdmin (and leaveGroup, which already relies
    /// on it) blocks unconditionally for the last admin — solo or not.
    /// This is pre-existing behavior this feature deliberately reuses
    /// rather than changing, so a solo admin still needs to archive their
    /// own cookbook first (via the new Archive Cookbook action) before
    /// deleting their account.
    @Test func blocksEvenWhenTheSoleAdminIsTheOnlyMember() async throws {
        let context = try makeInMemoryContext()
        let groups = InMemoryGroupsService()
        groups.creditsByUserID["alice"] = 1
        let group = try await groups.createGroup(makeDetails(name: "Solo", cookbookName: "Solo Cookbook"), creatorUserID: "alice", idempotencyKey: "req-1")

        await #expect(throws: AccountDeletionError.blockedByAdminOnlyCookbooks(cookbookNames: ["Solo Cookbook"])) {
            try await AccountDeletionCoordinator.deleteAllData(
                for: "alice",
                modelContext: context,
                groupsService: groups,
                entitlementService: InMemoryEntitlementService()
            )
        }
    }

    @Test func bestEffortDeletesTheEntitlementDocument() async throws {
        let context = try makeInMemoryContext()
        let entitlements = InMemoryEntitlementService()
        entitlements.entitlementsByUserID["alice"] = Entitlement(
            userID: "alice", creationCredits: 3, hasFamilyUser: false,
            familyUserPromoCreditAvailable: true, grantedPromoCredits: true, createdAt: .now
        )

        try await AccountDeletionCoordinator.deleteAllData(
            for: "alice",
            modelContext: context,
            groupsService: InMemoryGroupsService(),
            entitlementService: entitlements
        )

        #expect(entitlements.entitlementsByUserID["alice"] == nil)
    }
}
