//
//  FirestorePublicProfileService.swift
//  cookbook
//
//  Collection: publicProfiles/{userID}, one field (displayName). See
//  PublicProfileServicing's own doc comment for why this is a separate
//  collection from userProfiles rather than a field added there.
//

import FirebaseFirestore
import Foundation

final class FirestorePublicProfileService: PublicProfileServicing {
    private let db = Firestore.firestore()

    func setDisplayName(_ displayName: String, userID: String) async throws {
        try await db.collection("publicProfiles").document(userID).setData(["displayName": displayName], merge: true)
    }

    func fetchDisplayNames(userIDs: [String]) async throws -> [String: String] {
        let uniqueIDs = Array(Set(userIDs))
        guard !uniqueIDs.isEmpty else { return [:] }

        var result: [String: String] = [:]
        // Firestore's `in` operator caps at 30 values per query — a friend
        // list this large is unlikely today, but chunking costs nothing
        // and avoids a hard failure if it ever happens.
        for chunk in stride(from: 0, to: uniqueIDs.count, by: 30).map({ Array(uniqueIDs[$0..<min($0 + 30, uniqueIDs.count)]) }) {
            let snapshot = try await db.collection("publicProfiles")
                .whereField(FieldPath.documentID(), in: chunk)
                .getDocuments()
            for document in snapshot.documents {
                if let name = document.data()["displayName"] as? String {
                    result[document.documentID] = name
                }
            }
        }
        return result
    }
}
