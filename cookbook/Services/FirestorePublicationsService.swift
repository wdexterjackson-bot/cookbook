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
}
