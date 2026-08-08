//
//  FirestorePublicationsService.swift
//  cookbook
//
//  Collection: publications/{id}.
//

import FirebaseFirestore
import Foundation

final class FirestorePublicationsService: PublicationsServicing {
    private let db = Firestore.firestore()

    func publish(_ content: PublicationContentSnapshot, sourceRecipeID: String, to groupID: String, ownerUserID: String) async throws -> Publication {
        let existingSnapshot = try await db.collection("publications")
            .whereField("groupID", isEqualTo: groupID)
            .whereField("sourceRecipeID", isEqualTo: sourceRecipeID)
            .whereField("ownerUserID", isEqualTo: ownerUserID)
            .getDocuments()

        if let existingDocument = existingSnapshot.documents.first,
           var existing = try existingDocument.data(as: Publication?.self) {
            existing.content = content
            existing.state = .published
            existing.updatedAt = .now
            try existingDocument.reference.setData(from: existing)
            return existing
        }

        let publication = Publication(
            id: db.collection("publications").document().documentID,
            groupID: groupID,
            ownerUserID: ownerUserID,
            sourceRecipeID: sourceRecipeID,
            state: .published,
            publishedAt: .now,
            updatedAt: .now,
            content: content
        )
        try db.collection("publications").document(publication.id).setData(from: publication)
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
}
