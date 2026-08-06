//
//  FirestoreEntitlementGranter.swift
//  cookbook
//

import FirebaseFirestore
import Foundation

final class FirestoreEntitlementGranter: EntitlementGranting {
    func grantPromoCreditsIfEligible(userID: String, now: Date) async throws {
        guard PromoCredit.isEligible(on: now) else { return }

        let ref = Firestore.firestore().collection("entitlements").document(userID)
        // Only ever created once — a repeat call (e.g. a retried sign-up)
        // must not re-grant credits. firestore.rules (milestone 2C) is the
        // real enforcement of this; this check just avoids a needless write.
        let snapshot = try await ref.getDocument()
        guard !snapshot.exists else { return }

        try await ref.setData([
            "userID": userID,
            "creationCredits": PromoCredit.creditCount,
            "hasFamilyUser": false,
            "familyUserPromoCreditAvailable": true,
            "grantedPromoCredits": true,
            "createdAt": FieldValue.serverTimestamp(),
        ])
    }
}
