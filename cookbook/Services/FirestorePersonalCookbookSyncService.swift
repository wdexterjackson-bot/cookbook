//
//  FirestorePersonalCookbookSyncService.swift
//  cookbook
//
//  Collection: personalCookbooks/{cookbookID}, subcollection
//  personalCookbooks/{cookbookID}/recipes/{recipeID}.
//

import FirebaseFirestore
import Foundation

final class FirestorePersonalCookbookSyncService: PersonalCookbookSyncServicing {
    private let db = Firestore.firestore()

    func push(_ cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc], expectedRemoteUpdatedAt: Date?) async throws {
        let cookbookRef = db.collection("personalCookbooks").document(cookbook.id.uuidString)
        // A transaction, not a plain batch — the precondition check below
        // (has the remote doc changed since this device last saw it?)
        // needs to read and write atomically, or two devices pushing at
        // nearly the same moment could both pass the check against a
        // stale read before either write lands.
        _ = try await db.runTransaction { [db] transaction, errorPointer -> Any? in
            do {
                if let expectedRemoteUpdatedAt {
                    let existing = try transaction.getDocument(cookbookRef).data(as: PersonalCookbookDoc?.self)
                    // A tolerance, not exact equality — Swift Date <->
                    // Firestore Timestamp round-tripping can introduce
                    // sub-millisecond floating-point noise; a genuine
                    // conflicting edit differs by real seconds, not that.
                    let matchesExpected = existing.map { abs($0.updatedAt.timeIntervalSince(expectedRemoteUpdatedAt)) < 0.001 } ?? false
                    guard matchesExpected else {
                        errorPointer?.pointee = PersonalCookbookSyncError.remoteChangedSinceLastSync as NSError
                        return nil
                    }
                }
                try transaction.setData(from: cookbook, forDocument: cookbookRef)
                for recipe in recipes {
                    let recipeRef = cookbookRef.collection("recipes").document(recipe.id.uuidString)
                    try transaction.setData(from: recipe, forDocument: recipeRef)
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            return nil
        }
    }

    func fetchSyncedCookbooks(forUser userID: String) async throws -> [PersonalCookbookSummary] {
        let snapshot = try await db.collection("personalCookbooks")
            .whereField("ownerUserID", isEqualTo: userID)
            .getDocuments()
        let docs = try snapshot.documents.map { try $0.data(as: PersonalCookbookDoc.self) }
        return docs.map { PersonalCookbookSummary(id: $0.id, title: $0.title, updatedAt: $0.updatedAt) }
    }

    func pull(cookbookID: UUID, ownerUserID: String) async throws -> (cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc]) {
        let cookbookRef = db.collection("personalCookbooks").document(cookbookID.uuidString)
        guard let cookbook = try await cookbookRef.getDocument().data(as: PersonalCookbookDoc?.self) else {
            throw PersonalCookbookSyncError.notFound
        }
        // firestore.rules' recipes/{recipeID} read rule checks
        // resource.data.ownerUserID — Firestore only allows a list query
        // against a rule like that if the query itself carries a matching
        // filter (it validates the query's shape, not each document's
        // actual data), so an unfiltered getDocuments() here is rejected
        // outright with "Missing or insufficient permissions" even though
        // every real document in the subcollection would individually
        // pass the rule.
        let recipesSnapshot = try await cookbookRef.collection("recipes")
            .whereField("ownerUserID", isEqualTo: ownerUserID)
            .getDocuments()
        let recipes = try recipesSnapshot.documents.map { try $0.data(as: PersonalCookbookRecipeDoc.self) }
        return (cookbook, recipes)
    }

    func delete(cookbookID: UUID, ownerUserID: String) async throws {
        let cookbookRef = db.collection("personalCookbooks").document(cookbookID.uuidString)
        // Firestore doesn't cascade-delete subcollections when a parent
        // doc is deleted — the recipe subdocs need deleting explicitly,
        // in the same batch so a partial failure can't leave recipe
        // subdocs orphaned under a now-gone cookbook doc.
        let recipesSnapshot = try await cookbookRef.collection("recipes")
            .whereField("ownerUserID", isEqualTo: ownerUserID)
            .getDocuments()
        let batch = db.batch()
        for document in recipesSnapshot.documents {
            batch.deleteDocument(document.reference)
        }
        batch.deleteDocument(cookbookRef)
        try await batch.commit()
    }
}
