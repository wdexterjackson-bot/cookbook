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

        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        #expect(publication.state == .published)
        let fetched = try await service.fetchPublications(forGroup: "group-1")
        #expect(fetched.map(\.id) == [publication.id])
    }

    @Test func republishingSameRecipeUpdatesInPlaceInsteadOfDuplicating() async throws {
        let service = InMemoryPublicationsService()
        let first = try await service.publish(makeContent(title: "V1"), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        let second = try await service.publish(makeContent(title: "V2"), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        #expect(first.id == second.id)
        #expect(second.content.title == "V2")
        #expect(service.publications.count == 1)
    }

    @Test func unpublishRemovesItFromGroupFetch() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        try await service.unpublish(publication.id, actingUserID: "alice")

        let fetched = try await service.fetchPublications(forGroup: "group-1")
        #expect(fetched.isEmpty)
    }

    @Test func onlyOwnerCanUnpublish() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        await #expect(throws: PublicationsServiceError.notAuthorized) {
            try await service.unpublish(publication.id, actingUserID: "bob")
        }
    }

    @Test func coverImageURLRoundTripsThroughPublish() async throws {
        let service = InMemoryPublicationsService()
        var content = makeContent()
        content.coverImageURL = "https://example.com/photo.jpg"

        let publication = try await service.publish(content, sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        #expect(publication.content.coverImageURL == "https://example.com/photo.jpg")
    }

    @Test func newPublicationHasNoLikesYet() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        #expect(publication.likeCount == nil)
        #expect(try await service.hasLiked(publication.id, userID: "bob") == false)
    }

    @Test func likingIncrementsCountAndMarksTheUserAsHavingLiked() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        let newCount = try await service.setLiked(publication.id, userID: "bob", liked: true)

        #expect(newCount == 1)
        #expect(try await service.hasLiked(publication.id, userID: "bob") == true)
        #expect(service.publications.first?.likeCount == 1)
    }

    @Test func unlikingDecrementsCountBackDown() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")
        try await service.setLiked(publication.id, userID: "bob", liked: true)

        let newCount = try await service.setLiked(publication.id, userID: "bob", liked: false)

        #expect(newCount == 0)
        #expect(try await service.hasLiked(publication.id, userID: "bob") == false)
    }

    @Test func likingTwiceDoesNotDoubleCount() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        try await service.setLiked(publication.id, userID: "bob", liked: true)
        let secondCount = try await service.setLiked(publication.id, userID: "bob", liked: true)

        #expect(secondCount == 1)
    }

    @Test func likesFromDifferentUsersAccumulate() async throws {
        let service = InMemoryPublicationsService()
        let publication = try await service.publish(makeContent(), sourceRecipeID: "recipe-1", to: "group-1", ownerUserID: "alice")

        try await service.setLiked(publication.id, userID: "bob", liked: true)
        let countAfterCarol = try await service.setLiked(publication.id, userID: "carol", liked: true)

        #expect(countAfterCarol == 2)
    }
}
