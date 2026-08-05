//
//  FirestoreEntitlementService.swift
//  cookbook
//

import FirebaseFirestore
import Foundation

final class FirestoreEntitlementService: EntitlementServicing {
    private let db = Firestore.firestore()

    func fetchEntitlement(userID: String) async throws -> Entitlement? {
        try await db.collection("entitlements").document(userID).getDocument().data(as: Entitlement?.self)
    }
}
