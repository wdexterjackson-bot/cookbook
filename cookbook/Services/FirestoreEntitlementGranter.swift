//
//  FirestoreEntitlementGranter.swift
//  cookbook
//

import FirebaseFirestore
import Foundation

final class FirestoreEntitlementGranter: EntitlementGranting {
    func grantMissingLaunchCreditsIfEligible(userID: String, now: Date) async throws {
        guard LaunchCreditPromo.isEligible(on: now) else { return }

        let ref = Firestore.firestore().collection("entitlements").document(userID)
        _ = try await Firestore.firestore().runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                let data = snapshot.data() ?? [:]
                let receivedTier1 = data["receivedTier1PromoCredit"] as? Bool ?? false
                let receivedTier2 = data["receivedTier2PromoCredits"] as? Bool ?? false
                guard !receivedTier1 || !receivedTier2 else { return nil }

                var updates: [String: Any] = [:]
                if !receivedTier1 {
                    updates["tier1Credits"] = (data["tier1Credits"] as? Int ?? 0) + LaunchCreditPromo.tier1CreditCount
                    updates["receivedTier1PromoCredit"] = true
                }
                if !receivedTier2 {
                    updates["tier2Credits"] = (data["tier2Credits"] as? Int ?? 0) + LaunchCreditPromo.tier2CreditCount
                    updates["receivedTier2PromoCredits"] = true
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
