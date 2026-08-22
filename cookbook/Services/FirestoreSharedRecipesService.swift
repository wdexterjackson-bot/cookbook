//
//  FirestoreSharedRecipesService.swift
//  cookbook
//
//  Collection: sharedRecipes/{id}. Friendship gating happens in
//  firestore.rules (areFriends), not re-checked client-side — same
//  division of responsibility as everywhere else in this app (the client
//  attempts the write, the rules are the actual gate).
//

import FirebaseFirestore
import Foundation

final class FirestoreSharedRecipesService: SharedRecipesServicing {
    private let db = Firestore.firestore()

    @discardableResult
    func shareRecipe(
        content: PublicationContentSnapshot,
        sourceRecipeID: String,
        from senderID: String,
        to recipientID: String
    ) async throws -> SharedRecipe {
        let shared = SharedRecipe(
            id: SharedRecipe.compositeID(senderID: senderID, recipientID: recipientID, sourceRecipeID: sourceRecipeID),
            senderID: senderID,
            recipientID: recipientID,
            sourceRecipeID: sourceRecipeID,
            content: content,
            sharedAt: .now,
            state: .pending
        )
        // setData(from:) with no completion handler is fire-and-forget —
        // it returns as soon as encoding succeeds without ever waiting on
        // or surfacing the write's actual result, so a rules rejection
        // goes silently unnoticed (same real bug already found and fixed
        // in FirestoreChatService.sendMessage; see its own doc comment).
        // Encoding to a dictionary and using the plain setData(_:) gets
        // the real async throws overload instead.
        let encoded = try Firestore.Encoder().encode(shared)
        try await db.collection("sharedRecipes").document(shared.id).setData(encoded)
        return shared
    }

    func fetchSharedRecipes(forRecipient userID: String) async throws -> [SharedRecipe] {
        let snapshot = try await db.collection("sharedRecipes")
            .whereField("recipientID", isEqualTo: userID)
            .order(by: "sharedAt", descending: true)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: SharedRecipe.self) }
    }

    func fetchSharedRecipes(bySender userID: String) async throws -> [SharedRecipe] {
        let snapshot = try await db.collection("sharedRecipes")
            .whereField("senderID", isEqualTo: userID)
            .order(by: "sharedAt", descending: true)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: SharedRecipe.self) }
    }

    func markCopied(_ sharedRecipeID: String, recipientID: String) async throws {
        try await updateState(sharedRecipeID, recipientID: recipientID, to: .copied)
    }

    func decline(_ sharedRecipeID: String, recipientID: String) async throws {
        try await updateState(sharedRecipeID, recipientID: recipientID, to: .declined)
    }

    private func updateState(_ sharedRecipeID: String, recipientID: String, to state: SharedRecipeState) async throws {
        let ref = db.collection("sharedRecipes").document(sharedRecipeID)
        guard let shared = try await ref.getDocument().data(as: SharedRecipe?.self) else {
            throw SharedRecipesServiceError.notFound
        }
        guard shared.recipientID == recipientID else {
            throw SharedRecipesServiceError.notAuthorized
        }
        guard shared.state == .pending else {
            throw SharedRecipesServiceError.invalidState
        }
        try await ref.setData(["state": state.rawValue], merge: true)
    }
}
