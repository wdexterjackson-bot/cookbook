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
}
