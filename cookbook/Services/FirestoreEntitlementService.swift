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

    @discardableResult
    func redeemFamilyUserPromoCredit(userID: String) async throws -> Bool {
        let ref = db.collection("entitlements").document(userID)

        let result: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(ref)
                let promoAvailable = snapshot.data()?["familyUserPromoCreditAvailable"] as? Bool ?? false
                let alreadyFamilyUser = snapshot.data()?["hasFamilyUser"] as? Bool ?? false
                guard promoAvailable, !alreadyFamilyUser else {
                    return false
                }

                transaction.setData([
                    "familyUserPromoCreditAvailable": false,
                    "hasFamilyUser": true,
                ], forDocument: ref, merge: true)
                return true
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }

        return (result as? Bool) ?? false
    }

    func deleteEntitlement(userID: String) async throws {
        try await db.collection("entitlements").document(userID).delete()
    }
}
