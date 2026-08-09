//
//  FirestoreUserProfileService.swift
//  cookbook
//

import FirebaseFirestore
import Foundation

final class FirestoreUserProfileService: UserProfileServicing {
    private let db = Firestore.firestore()

    func fetchLocation(userID: String) async throws -> UserLocation? {
        try await db.collection("userProfiles").document(userID).getDocument().data(as: UserLocation?.self)
    }

    func setLocation(_ location: UserLocation, userID: String) async throws {
        // setData(from:merge:) (the Codable convenience) has no async
        // overload — it's fire-and-forget with a completion closure that's
        // easy to forget to pass, so a genuine write failure (rules
        // rejection, etc.) was silently swallowed while the caller still
        // marked the save as successful. Encoding to a dictionary first and
        // calling the plain setData(_:merge:) gets the real async throws
        // overload instead, same pattern FirestoreMessagingService already
        // uses for its own writes.
        let encoded = try Firestore.Encoder().encode(location)
        try await db.collection("userProfiles").document(userID).setData(encoded, merge: true)
    }

    func deleteProfile(userID: String) async throws {
        try await db.collection("userProfiles").document(userID).delete()
    }
}
