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
        try db.collection("userProfiles").document(userID).setData(from: location, merge: true)
    }

    func deleteProfile(userID: String) async throws {
        try await db.collection("userProfiles").document(userID).delete()
    }
}
