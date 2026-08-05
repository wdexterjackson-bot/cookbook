//
//  InMemoryPublicationsService.swift
//  cookbook
//

import Foundation

final class InMemoryPublicationsService: PublicationsServicing {
    private(set) var publications: [Publication] = []

    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, ownerUserID: String) async throws -> Publication {
        if let index = publications.firstIndex(where: { $0.groupID == groupID && $0.sourceRecipeID == sourceRecipeID && $0.ownerUserID == ownerUserID }) {
            publications[index].content = content
            publications[index].state = .published
            publications[index].updatedAt = .now
            return publications[index]
        }

        let publication = Publication(
            id: UUID().uuidString,
            groupID: groupID,
            ownerUserID: ownerUserID,
            sourceRecipeID: sourceRecipeID,
            state: .published,
            publishedAt: .now,
            updatedAt: .now,
            content: content
        )
        publications.append(publication)
        return publication
    }

    func unpublish(_ publicationID: String, actingUserID: String) async throws {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publications[index].ownerUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        publications[index].state = .unpublished
        publications[index].updatedAt = .now
    }

    func fetchPublications(forGroup groupID: String) async throws -> [Publication] {
        publications.filter { $0.groupID == groupID && $0.state == .published }
    }

    func fetchPublication(id: String) async throws -> Publication? {
        publications.first { $0.id == id }
    }
}
