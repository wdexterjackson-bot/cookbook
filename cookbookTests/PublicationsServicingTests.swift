//
//  PublicationsServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct PublicationsServicingTests {

    private func makeContent(title: String = "Skillet Cornbread") -> PublicationContentSnapshot {
        PublicationContentSnapshot(
            title: title,
            summary: "",
            yield: "Serves 8",
            totalTimeMinutes: 40,
            ingredientSections: [],
            stepSections: [],
            notes: "",
            tags: []
        )
    }

    @Test func publishCreatesANewPublication() async throws {
        let service = InMemoryPublicationsService()

        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        #expect(publication.state == .published)
        let fetched = try await service.fetchPublications(forGroup: "group-1")
        #expect(fetched.map(\.id) == [publication.id])
    }

    @Test func republishingSameRecipeUpdatesInPlaceInsteadOfDuplicating() async throws {
        let service = InMemoryPublicationsService()
        let first = try await service.publish(makeContent(title: "V1"), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        let second = try await service.publish(makeContent(title: "V2"), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        #expect(first.id == second.id)
        #expect(second.content.title == "V2")
        #expect(service.publications.count == 1)
    }

    @Test func unpublishRemovesItFromGroupFetch() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        try await service.unpublish(publication.id, actingUserID: "alice")

        let fetched = try await service.fetchPublications(forGroup: "group-1")
        #expect(fetched.isEmpty)
    }

    @Test func onlyOwnerCanUnpublish() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        await #expect(throws: PublicationsServiceError.notAuthorized) {
            try await service.unpublish(publication.id, actingUserID: "bob")
        }
    }

    @Test func coverImageURLRoundTripsThroughPublish() async throws {
        let service = InMemoryPublicationsService()
        var content = makeContent()
        content.coverImageURL = "https://example.com/photo.jpg"

        let publication = try await service.publish(content, sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        #expect(publication.content.coverImageURL == "https://example.com/photo.jpg")
    }

    @Test func newPublicationHasNoLikesYet() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        #expect(publication.likeCount == nil)
        #expect(try await service.hasLiked(publication.id, userID: "bob") == false)
    }

    @Test func likingIncrementsCountAndMarksTheUserAsHavingLiked() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        let newCount = try await service.setLiked(publication.id, userID: "bob", liked: true)

        #expect(newCount == 1)
        #expect(try await service.hasLiked(publication.id, userID: "bob") == true)
        #expect(service.publications.first?.likeCount == 1)
    }

    @Test func unlikingDecrementsCountBackDown() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")
        try await service.setLiked(publication.id, userID: "bob", liked: true)

        let newCount = try await service.setLiked(publication.id, userID: "bob", liked: false)

        #expect(newCount == 0)
        #expect(try await service.hasLiked(publication.id, userID: "bob") == false)
    }

    @Test func likingTwiceDoesNotDoubleCount() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        try await service.setLiked(publication.id, userID: "bob", liked: true)
        let secondCount = try await service.setLiked(publication.id, userID: "bob", liked: true)

        #expect(secondCount == 1)
    }

    @Test func likesFromDifferentUsersAccumulate() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        try await service.setLiked(publication.id, userID: "bob", liked: true)
        let countAfterCarol = try await service.setLiked(publication.id, userID: "carol", liked: true)

        #expect(countAfterCarol == 2)
    }

    @Test func publishingTheSameRecipeToADifferentCookbookInTheSameGroupCreatesASeparatePublication() async throws {
        let service = InMemoryPublicationsService()
        let first = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        let second = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-2", ownerUserID: "alice")

        #expect(first.id != second.id)
        #expect(service.publications.count == 2)
    }

    @Test func ownerCanDeleteTheirOwnPublication() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")

        try await service.deletePublication(publication.id, actingUserID: "alice")

        #expect(try await service.fetchPublication(id: publication.id) == nil)
    }

    @Test func adminCanDeleteSomeoneElsesPublication() async throws {
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await groups.createGroup(
            NewGroupDetails(name: "Barrentines", description: "", type: "Family", locationText: "Memphis, TN", structuredRegion: nil, visibility: .publicGroup, allowsMemberInvites: false, approvalPolicy: .anyAdministrator),
            cookbookDetails: NewGroupCookbookDetails(cookbookName: "Reunion", allowsMemberPublishing: true),
            creatorUserID: "alice", creatorDisplayName: "Alice", idempotencyKey: "req-1"
        )
        let service = InMemoryPublicationsService(groupsService: groups)
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: group.id, cookbookID: "cb-1", ownerUserID: "bob")

        try await service.deletePublication(publication.id, actingUserID: "alice")

        #expect(try await service.fetchPublication(id: publication.id) == nil)
    }

    @Test func nonOwnerNonAdminCannotDeleteSomeoneElsesPublication() async throws {
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await groups.createGroup(
            NewGroupDetails(name: "Barrentines", description: "", type: "Family", locationText: "Memphis, TN", structuredRegion: nil, visibility: .publicGroup, allowsMemberInvites: false, approvalPolicy: .anyAdministrator),
            cookbookDetails: NewGroupCookbookDetails(cookbookName: "Reunion", allowsMemberPublishing: true),
            creatorUserID: "alice", creatorDisplayName: "Alice", idempotencyKey: "req-1"
        )
        let service = InMemoryPublicationsService(groupsService: groups)
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: group.id, cookbookID: "cb-1", ownerUserID: "bob")

        await #expect(throws: PublicationsServiceError.notAuthorized) {
            try await service.deletePublication(publication.id, actingUserID: "carol")
        }
    }

    @Test func commentingRequiresCommentsToBeEnabled() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")
        // commentsEnabled defaults to false — never explicitly turned on.

        await #expect(throws: PublicationsServiceError.commentsDisabled) {
            try await service.addComment(publication.id, authorUserID: "bob", authorDisplayName: "Bob", text: "Yum!")
        }
    }

    @Test func addingAndFetchingCommentsWhenEnabled() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")
        try await service.setCommentsEnabled(publication.id, enabled: true, actingUserID: "alice")

        _ = try await service.addComment(publication.id, authorUserID: "bob", authorDisplayName: "Bob", text: "Yum!")

        let comments = try await service.fetchComments(publication.id)
        #expect(comments.map(\.text) == ["Yum!"])
        #expect(comments.first?.authorDisplayName == "Bob")
    }

    @Test func authorCanDeleteTheirOwnComment() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", cookbookID: "cb-1", ownerUserID: "alice")
        try await service.setCommentsEnabled(publication.id, enabled: true, actingUserID: "alice")
        let comment = try await service.addComment(publication.id, authorUserID: "bob", authorDisplayName: "Bob", text: "Yum!")

        try await service.deleteComment(comment.id, publicationID: publication.id, actingUserID: "bob")

        #expect(try await service.fetchComments(publication.id).isEmpty)
    }

    @Test func adminCanDeleteSomeoneElsesComment() async throws {
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await groups.createGroup(
            NewGroupDetails(name: "Barrentines", description: "", type: "Family", locationText: "Memphis, TN", structuredRegion: nil, visibility: .publicGroup, allowsMemberInvites: false, approvalPolicy: .anyAdministrator),
            cookbookDetails: NewGroupCookbookDetails(cookbookName: "Reunion", allowsMemberPublishing: true),
            creatorUserID: "alice", creatorDisplayName: "Alice", idempotencyKey: "req-1"
        )
        let service = InMemoryPublicationsService(groupsService: groups)
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: group.id, cookbookID: "cb-1", ownerUserID: "alice")
        try await service.setCommentsEnabled(publication.id, enabled: true, actingUserID: "alice")
        let comment = try await service.addComment(publication.id, authorUserID: "bob", authorDisplayName: "Bob", text: "Yum!")

        try await service.deleteComment(comment.id, publicationID: publication.id, actingUserID: "alice")

        #expect(try await service.fetchComments(publication.id).isEmpty)
    }

    @Test func nonAuthorNonAdminCannotDeleteSomeoneElsesComment() async throws {
        let groups = InMemoryGroupsService()
        groups.tier2CreditsByUserID["alice"] = 1
        let (group, _) = try await groups.createGroup(
            NewGroupDetails(name: "Barrentines", description: "", type: "Family", locationText: "Memphis, TN", structuredRegion: nil, visibility: .publicGroup, allowsMemberInvites: false, approvalPolicy: .anyAdministrator),
            cookbookDetails: NewGroupCookbookDetails(cookbookName: "Reunion", allowsMemberPublishing: true),
            creatorUserID: "alice", creatorDisplayName: "Alice", idempotencyKey: "req-1"
        )
        let service = InMemoryPublicationsService(groupsService: groups)
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: group.id, cookbookID: "cb-1", ownerUserID: "alice")
        try await service.setCommentsEnabled(publication.id, enabled: true, actingUserID: "alice")
        let comment = try await service.addComment(publication.id, authorUserID: "bob", authorDisplayName: "Bob", text: "Yum!")

        await #expect(throws: PublicationsServiceError.notAuthorized) {
            try await service.deleteComment(comment.id, publicationID: publication.id, actingUserID: "carol")
        }
    }
}
