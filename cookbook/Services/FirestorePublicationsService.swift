//
//  FirestorePublicationsService.swift
//  cookbook
//
//  Collections: publications/{id}, publications/{id}/comments/{id}.
//

import FirebaseFirestore
import Foundation

final class FirestorePublicationsService: PublicationsServicing {
    private let db = Firestore.firestore()
    private let groupsService: GroupsServicing

    init(groupsService: GroupsServicing = FirestoreGroupsService()) {
        self.groupsService = groupsService
    }

    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, cookbookID: String, ownerUserID: String) async throws -> Publication {
        let ref = db.collection("publications").document(
            Publication.compositeID(groupID: groupID, cookbookID: cookbookID, sourceRecipeID: sourceRecipeID, ownerUserID: ownerUserID)
        )
        let existing = try? await ref.getDocument().data(as: Publication?.self)

        let publication = Publication(
            id: ref.documentID,
            groupID: groupID,
            cookbookID: cookbookID,
            ownerUserID: ownerUserID,
            sourceRecipeID: sourceRecipeID,
            state: .published,
            publishedAt: existing?.publishedAt ?? .now,
            updatedAt: .now,
            content: content,
            likeCount: existing?.likeCount,
            ratingSum: existing?.ratingSum,
            ratingCount: existing?.ratingCount,
            commentsEnabled: existing?.commentsEnabled ?? false
        )
        try ref.setData(from: publication)
        return publication
    }

    func unpublish(_ publicationID: String, actingUserID: String) async throws {
        let ref = db.collection("publications").document(publicationID)
        guard var publication = try await ref.getDocument().data(as: Publication?.self) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publication.ownerUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        publication.state = .unpublished
        publication.updatedAt = .now
        try ref.setData(from: publication)
    }

    func setCommentsEnabled(_ publicationID: String, enabled: Bool, actingUserID: String) async throws {
        let ref = db.collection("publications").document(publicationID)
        guard var publication = try await ref.getDocument().data(as: Publication?.self) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publication.ownerUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        publication.commentsEnabled = enabled
        try ref.setData(from: publication)
    }

    func deletePublication(_ publicationID: String, actingUserID: String) async throws {
        let ref = db.collection("publications").document(publicationID)
        guard let publication = try await ref.getDocument().data(as: Publication?.self) else {
            throw PublicationsServiceError.publicationNotFound
        }
        if publication.ownerUserID != actingUserID {
            let groupMemberships = try await groupsService.fetchMemberships(forGroup: publication.groupID)
            guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
                throw PublicationsServiceError.notAuthorized
            }
        }
        // Firestore never cascade-deletes subcollections — without this,
        // every comment ever posted here would survive as an orphan,
        // unreachable once the parent publication is gone from the UI but
        // still sitting there forever. Owner-or-admin (just proven above)
        // is exactly who comments/delete already lets delete any comment
        // here, so this is never blocked by rules the caller hasn't
        // already cleared.
        let commentsSnapshot = try await ref.collection("comments").getDocuments()
        for commentDoc in commentsSnapshot.documents {
            try await commentDoc.reference.delete()
        }
        try await ref.delete()
    }

    func fetchComments(_ publicationID: String) async throws -> [RecipeComment] {
        let snapshot = try await db.collection("publications").document(publicationID)
            .collection("comments")
            .order(by: "createdAt")
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: RecipeComment.self) }
    }

    func addComment(_ publicationID: String, authorUserID: String, authorDisplayName: String, text: String) async throws -> RecipeComment {
        guard let publication = try await fetchPublication(id: publicationID) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publication.commentsEnabled else {
            throw PublicationsServiceError.commentsDisabled
        }
        let comment = RecipeComment(
            id: db.collection("publications").document(publicationID).collection("comments").document().documentID,
            publicationID: publicationID,
            groupID: publication.groupID,
            authorUserID: authorUserID,
            authorDisplayName: authorDisplayName,
            text: text,
            createdAt: .now
        )
        try db.collection("publications").document(publicationID).collection("comments").document(comment.id).setData(from: comment)
        return comment
    }

    func deleteComment(_ commentID: String, publicationID: String, actingUserID: String) async throws {
        let ref = db.collection("publications").document(publicationID).collection("comments").document(commentID)
        guard let comment = try await ref.getDocument().data(as: RecipeComment?.self) else {
            throw PublicationsServiceError.commentNotFound
        }
        if comment.authorUserID != actingUserID {
            let groupMemberships = try await groupsService.fetchMemberships(forGroup: comment.groupID)
            guard GroupPolicy.isActiveAdmin(actingUserID, in: groupMemberships) else {
                throw PublicationsServiceError.notAuthorized
            }
        }
        try await ref.delete()
    }

    func fetchPublications(forGroup groupID: String) async throws -> [Publication] {
        let snapshot = try await db.collection("publications")
            .whereField("groupID", isEqualTo: groupID)
            .whereField("state", isEqualTo: PublicationState.published.rawValue)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: Publication.self) }
    }

    func fetchPublication(id: String) async throws -> Publication? {
        try await db.collection("publications").document(id).getDocument().data(as: Publication?.self)
    }

    func fetchPublications(forOwner ownerUserID: String, groupID: String) async throws -> [Publication] {
        let snapshot = try await db.collection("publications")
            .whereField("groupID", isEqualTo: groupID)
            .whereField("ownerUserID", isEqualTo: ownerUserID)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: Publication.self) }
    }

    func fetchAllPublications(forGroup groupID: String) async throws -> [Publication] {
        let snapshot = try await db.collection("publications")
            .whereField("groupID", isEqualTo: groupID)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: Publication.self) }
    }

    func tombstoneOwnerAttribution(_ publicationID: String, actingUserID: String) async throws {
        let ref = db.collection("publications").document(publicationID)
        guard var publication = try await ref.getDocument().data(as: Publication?.self) else {
            throw PublicationsServiceError.publicationNotFound
        }
        guard publication.ownerUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        publication.content.authorLineage = "Original contributor deleted"
        publication.updatedAt = .now
        try ref.setData(from: publication)
    }

    func tombstoneCommentAuthorship(_ commentID: String, publicationID: String, actingUserID: String) async throws {
        let ref = db.collection("publications").document(publicationID).collection("comments").document(commentID)
        guard var comment = try await ref.getDocument().data(as: RecipeComment?.self) else {
            throw PublicationsServiceError.commentNotFound
        }
        guard comment.authorUserID == actingUserID else {
            throw PublicationsServiceError.notAuthorized
        }
        comment.authorDisplayName = "Deleted User"
        try ref.setData(from: comment)
    }

    func hasLiked(_ publicationID: String, userID: String) async throws -> Bool {
        let doc = try await db.collection("publications").document(publicationID)
            .collection("likes").document(userID).getDocument()
        return doc.exists
    }

    @discardableResult
    func setLiked(_ publicationID: String, userID: String, liked: Bool) async throws -> Int {
        let publicationRef = db.collection("publications").document(publicationID)
        let likeRef = publicationRef.collection("likes").document(userID)

        let result: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let publicationSnapshot = try transaction.getDocument(publicationRef)
                let currentCount = publicationSnapshot.data()?["likeCount"] as? Int ?? 0
                let alreadyLiked = try transaction.getDocument(likeRef).exists

                if liked, !alreadyLiked {
                    let newCount = currentCount + 1
                    transaction.setData(["userID": userID, "likedAt": FieldValue.serverTimestamp()], forDocument: likeRef)
                    transaction.updateData(["likeCount": newCount], forDocument: publicationRef)
                    return newCount
                } else if !liked, alreadyLiked {
                    let newCount = max(0, currentCount - 1)
                    transaction.deleteDocument(likeRef)
                    transaction.updateData(["likeCount": newCount], forDocument: publicationRef)
                    return newCount
                }
                return currentCount
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        return (result as? Int) ?? 0
    }

    func myRating(_ publicationID: String, userID: String) async throws -> Int? {
        let doc = try await db.collection("publications").document(publicationID)
            .collection("ratings").document(userID).getDocument()
        return doc.data()?["rating"] as? Int
    }

    @discardableResult
    func setRating(_ publicationID: String, userID: String, rating: Int) async throws -> (sum: Int, count: Int) {
        try await updateRating(publicationID, userID: userID, newRating: rating)
    }

    @discardableResult
    func clearRating(_ publicationID: String, userID: String) async throws -> (sum: Int, count: Int) {
        try await updateRating(publicationID, userID: userID, newRating: nil)
    }

    /// Shared by setRating/clearRating — reads the rater's prior value (if
    /// any) so the aggregate can be adjusted by the exact delta rather than
    /// re-derived, same read-modify-write shape as setLiked.
    private func updateRating(_ publicationID: String, userID: String, newRating: Int?) async throws -> (sum: Int, count: Int) {
        let publicationRef = db.collection("publications").document(publicationID)
        let ratingRef = publicationRef.collection("ratings").document(userID)

        let result: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let publicationSnapshot = try transaction.getDocument(publicationRef)
                let currentSum = publicationSnapshot.data()?["ratingSum"] as? Int ?? 0
                let currentCount = publicationSnapshot.data()?["ratingCount"] as? Int ?? 0
                let oldRating = try transaction.getDocument(ratingRef).data()?["rating"] as? Int

                var newSum = currentSum
                var newCount = currentCount

                switch (oldRating, newRating) {
                case (nil, let new?):
                    newSum += new
                    newCount += 1
                    transaction.setData(["userID": userID, "rating": new, "ratedAt": FieldValue.serverTimestamp()], forDocument: ratingRef)
                case (let old?, let new?):
                    newSum += (new - old)
                    transaction.setData(["userID": userID, "rating": new, "ratedAt": FieldValue.serverTimestamp()], forDocument: ratingRef)
                case (let old?, nil):
                    newSum -= old
                    newCount = max(0, newCount - 1)
                    transaction.deleteDocument(ratingRef)
                case (nil, nil):
                    break
                }
                newSum = max(0, newSum)

                transaction.updateData(["ratingSum": newSum, "ratingCount": newCount], forDocument: publicationRef)
                return ["sum": newSum, "count": newCount]
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        guard let pair = result as? [String: Int], let sum = pair["sum"], let count = pair["count"] else {
            return (0, 0)
        }
        return (sum, count)
    }
}
