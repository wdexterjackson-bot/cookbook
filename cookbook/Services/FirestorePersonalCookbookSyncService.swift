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

    func push(_ cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc]) async throws {
        let cookbookRef = db.collection("personalCookbooks").document(cookbook.id.uuidString)
        let batch = db.batch()
        try batch.setData(from: cookbook, forDocument: cookbookRef)
        for recipe in recipes {
            let recipeRef = cookbookRef.collection("recipes").document(recipe.id.uuidString)
            try batch.setData(from: recipe, forDocument: recipeRef)
        }
        try await batch.commit()
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
