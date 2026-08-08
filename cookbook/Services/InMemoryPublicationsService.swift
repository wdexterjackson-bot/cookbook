//
//  InMemoryPublicationsService.swift
//  cookbook
//

import Foundation

final class InMemoryPublicationsService: PublicationsServicing {
    private(set) var publications: [Publication] = []
    private var likedUserIDsByPublicationID: [String: Set<String>] = [:]

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

    func hasLiked(_ publicationID: String, userID: String) async throws -> Bool {
        likedUserIDsByPublicationID[publicationID]?.contains(userID) ?? false
    }

    @discardableResult
    func setLiked(_ publicationID: String, userID: String, liked: Bool) async throws -> Int {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        var likedUsers = likedUserIDsByPublicationID[publicationID] ?? []
        let alreadyLiked = likedUsers.contains(userID)
        let currentCount = publications[index].likeCount ?? 0

        if liked, !alreadyLiked {
            likedUsers.insert(userID)
            publications[index].likeCount = currentCount + 1
        } else if !liked, alreadyLiked {
            likedUsers.remove(userID)
            publications[index].likeCount = max(0, currentCount - 1)
        }
        likedUserIDsByPublicationID[publicationID] = likedUsers
        return publications[index].likeCount ?? 0
    }
}
