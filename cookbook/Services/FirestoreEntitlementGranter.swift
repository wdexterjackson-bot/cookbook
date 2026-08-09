//
//  FirestoreEntitlementGranter.swift
//  cookbook
//

import FirebaseFirestore
import Foundation

final class FirestoreEntitlementGranter: EntitlementGranting {
    /// Each tier's grant is gated by its own expiration date, independent
    /// of the other — a new signup after tier1's window closes (2027) but
    /// before tier2's (2029) still gets their tier2 credits, just not
    /// tier1's, and vice versa once both windows have passed (a no-op).
    func grantMissingLaunchCreditsIfEligible(userID: String, now: Date) async throws {
        let ref = Firestore.firestore().collection("entitlements").document(userID)
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                let data = snapshot.data() ?? [:]
                let receivedTier1 = data["receivedTier1PromoCredit"] as? Bool ?? false
                let receivedTier2 = data["receivedTier2PromoCredits"] as? Bool ?? false
                let grantTier1 = !receivedTier1 && LaunchCreditPromo.isTier1Eligible(on: now)
                let grantTier2 = !receivedTier2 && LaunchCreditPromo.isTier2Eligible(on: now)
                guard grantTier1 || grantTier2 else { return nil }

                var updates: [String: Any] = [:]
                if grantTier1 {
                    updates["tier1Credits"] = (data["tier1Credits"] as? Int ?? 0) + LaunchCreditPromo.tier1CreditCount
                    updates["receivedTier1PromoCredit"] = true
                    updates["tier1ExpiresAt"] = Timestamp(date: LaunchCreditPromo.tier1ExpirationDate)
                }
                if grantTier2 {
                    updates["tier2Credits"] = (data["tier2Credits"] as? Int ?? 0) + LaunchCreditPromo.tier2CreditCount
                    updates["receivedTier2PromoCredits"] = true
                    updates["tier2ExpiresAt"] = Timestamp(date: LaunchCreditPromo.tier2ExpirationDate)
                }

                if snapshot.exists {
                    transaction.setData(updates, forDocument: ref, merge: true)
                } else {
                    let defaults: [String: Any] = [
                        "userID": userID,
                        "tier1Credits": 0,
                        "tier2Credits": 0,
                        "isProUser": false,
                        "receivedTier1PromoCredit": false,
                        "receivedTier2PromoCredits": false,
                        "createdAt": FieldValue.serverTimestamp(),
                    ]
                    // `updates`' own computed values win over these
                    // placeholders wherever both set the same key.
                    transaction.setData(updates.merging(defaults) { computed, _ in computed }, forDocument: ref)
                }
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }
}
