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

    /// Lowercased before storing — email search (findUserByEmail) does an
    /// exact-match Firestore query, and a federated sign-in provider
    /// (Apple/Google) can hand back a mixed-case email that a person would
    /// never type mixed-case into the search field themselves. Normalizing
    /// once here, on every sign-in (this runs unconditionally via
    /// PostSignInCoordinator, not just at account creation), is what keeps
    /// every existing account self-healing on its next sign-in rather than
    /// needing a one-off data migration.
    func setEmail(_ email: String, userID: String) async throws {
        try await db.collection("userProfiles").document(userID).setData(["email": email.lowercased()], merge: true)
    }

    func fetchIsEmailDiscoverable(userID: String) async throws -> Bool {
        let doc = try await db.collection("userProfiles").document(userID).getDocument()
        return doc.data()?["isEmailDiscoverable"] as? Bool ?? true
    }

    func setEmailDiscoverable(_ discoverable: Bool, userID: String) async throws {
        try await db.collection("userProfiles").document(userID).setData(["isEmailDiscoverable": discoverable], merge: true)
    }

    func deleteProfile(userID: String) async throws {
        try await db.collection("userProfiles").document(userID).delete()
    }
}
