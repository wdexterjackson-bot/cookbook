//
//  InMemoryPublicationsService.swift
//  cookbook
//

import Foundation

final class InMemoryPublicationsService: PublicationsServicing {
    private(set) var publications: [Publication] = []
    private(set) var comments: [RecipeComment] = []
    private var likedUserIDsByPublicationID: [String: Set<String>] = [:]
    private var ratingsByPublicationID: [String: [String: Int]] = [:]
    private let groupsService: GroupsServicing

    init(groupsService: GroupsServicing = InMemoryGroupsService()) {
        self.groupsService = groupsService
    }

    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, cookbookID: String, ownerUserID: String) async throws -> Publication {
        if let index = publications.firstIndex(where: {
            $0.groupID == groupID && $0.cookbookID == cookbookID && $0.sourceRecipeID == sourceRecipeID && $0.ownerUserID == ownerUserID
        }) {
            publications[index].content = content
            publications[index].state = .published
            publications[index].updatedAt = .now
            return publications[index]
        }

        let publication = Publication(
            id: UUID().uuidString,
            groupID: groupID,
            cookbookID: cookbookID,
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

    func setCommentsEnabled(_ publicationID: String, enabled: Bool, actingUserID: String) async throws {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publications[index].ownerUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        publications[index].commentsEnabled = enabled
    }

    func deletePublication(_ publicationID: String, actingUserID: String) async throws {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        let publication = publications[index]
        if publication.ownerUserID != actingUserID {
            let groupMemberships = try await groupsService.fetchMemberships(forGroup: publication.groupID)
            guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
                throw PublicationsServiceError.notAuthorized
            }
        }
        publications.remove(at: index)
        comments.removeAll { $0.publicationID == publicationID }
    }

    func fetchComments(_ publicationID: String) async throws -> [RecipeComment] {
        comments.filter { $0.publicationID == publicationID }.sorted { $0.createdAt < $1.createdAt }
    }

    func addComment(_ publicationID: String, authorUserID: String, authorDisplayName: String, text: String) async throws -> RecipeComment {
        guard let publication = publications.first(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publication.commentsEnabled else {
            throw PublicationsServiceError.commentsDisabled
        }
        let comment = RecipeComment(
            id: UUID().uuidString,
            publicationID: publicationID,
            groupID: publication.groupID,
            authorUserID: authorUserID,
            authorDisplayName: authorDisplayName,
            text: text,
            createdAt: .now
        )
        comments.append(comment)
        return comment
    }

    func deleteComment(_ commentID: String, publicationID: String, actingUserID: String) async throws {
        guard let index = comments.firstIndex(where: { $0.id == commentID && $0.publicationID == publicationID }) else {
            throw PublicationsServiceError.commentNotFound
        }
        let comment = comments[index]
        if comment.authorUserID != actingUserID {
            let groupMemberships = try await groupsService.fetchMemberships(forGroup: comment.groupID)
            guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
                throw PublicationsServiceError.notAuthorized
            }
        }
        comments.remove(at: index)
    }

    func fetchPublications(forGroup groupID: String) async throws -> [Publication] {
        publications.filter { $0.groupID == groupID && $0.state == .published }
    }

    func fetchPublication(id: String) async throws -> Publication? {
        publications.first { $0.id == id }
    }

    func fetchPublications(forOwner ownerUserID: String, groupID: String) async throws -> [Publication] {
        publications.filter { $0.groupID == groupID && $0.ownerUserID == ownerUserID }
    }

    func tombstoneOwnerAttribution(_ publicationID: String, actingUserID: String) async throws {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publications[index].ownerUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        publications[index].content.authorLineage = "Original contributor deleted"
        publications[index].updatedAt = .now
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

    func myRating(_ publicationID: String, userID: String) async throws -> Int? {
        ratingsByPublicationID[publicationID]?[userID]
    }

    @discardableResult
    func setRating(_ publicationID: String, userID: String, rating: Int) async throws -> (sum: Int, count: Int) {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        var ratings = ratingsByPublicationID[publicationID] ?? [:]
        let oldRating = ratings[userID]
        var sum = publications[index].ratingSum ?? 0
        var count = publications[index].ratingCount ?? 0
        if let oldRating {
            sum += (rating - oldRating)
        } else {
            sum += rating
            count += 1
        }
        ratings[userID] = rating
        ratingsByPublicationID[publicationID] = ratings
        publications[index].ratingSum = max(0, sum)
        publications[index].ratingCount = count
        return (publications[index].ratingSum ?? 0, count)
    }

    @discardableResult
    func clearRating(_ publicationID: String, userID: String) async throws -> (sum: Int, count: Int) {
        guard let index = publications.firstIndex(where: { $0.id == publicationID }) else {
            throw PublicationsServiceError.publicationNotFound
        }
        var ratings = ratingsByPublicationID[publicationID] ?? [:]
        guard let oldRating = ratings[userID] else {
            return (publications[index].ratingSum ?? 0, publications[index].ratingCount ?? 0)
        }
        ratings[userID] = nil
        ratingsByPublicationID[publicationID] = ratings
        let sum = max(0, (publications[index].ratingSum ?? 0) - oldRating)
        let count = max(0, (publications[index].ratingCount ?? 0) - 1)
        publications[index].ratingSum = sum
        publications[index].ratingCount = count
        return (sum, count)
    }
}
