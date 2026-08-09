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
    func redeemTier1CreditForProUser(userID: String) async throws -> Bool {
        let ref = db.collection("entitlements").document(userID)

        let result: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(ref)
                let tier1Credits = snapshot.data()?["tier1Credits"] as? Int ?? 0
                let alreadyPro = snapshot.data()?["isProUser"] as? Bool ?? false
                guard tier1Credits > 0, !alreadyPro else {
                    return false
                }
                // Checked in the same transaction as the credit count
                // itself, same reasoning as FirestoreGroupsService.createGroup's
                // matching check — the rules-side tier1NotExpired check is
                // the real enforcement, this is just for a clean error.
                if let expiresAt = (snapshot.data()?["tier1ExpiresAt"] as? Timestamp)?.dateValue(), expiresAt < Date() {
                    errorPointer?.pointee = EntitlementServiceError.creditExpired as NSError
                    return nil
                }

                transaction.setData([
                    "tier1Credits": tier1Credits - 1,
                    "isProUser": true,
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
