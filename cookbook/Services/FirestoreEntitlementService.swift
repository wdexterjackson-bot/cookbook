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

    func applyDiscountCode(_ code: String, userID: String) async throws {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard DiscountCodePromo.isValid(trimmed) else {
            throw EntitlementServiceError.invalidDiscountCode
        }
        let ref = db.collection("entitlements").document(userID)

        try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(ref)
                let redeemedCodes = snapshot.data()?["redeemedDiscountCodes"] as? [String] ?? []
                guard !redeemedCodes.contains(trimmed) else {
                    errorPointer?.pointee = EntitlementServiceError.discountCodeAlreadyRedeemed as NSError
                    return nil
                }
                let currentCredits = snapshot.data()?["annualProMembershipCredits"] as? Int ?? 0
                transaction.setData([
                    "redeemedDiscountCodes": redeemedCodes + [trimmed],
                    "annualProMembershipCredits": currentCredits + 1,
                ], forDocument: ref, merge: true)
                return nil
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
    }

    @discardableResult
    func redeemAnnualProMembershipCredit(userID: String) async throws -> Bool {
        let ref = db.collection("entitlements").document(userID)

        let result: Any = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let snapshot = try transaction.getDocument(ref)
                let credits = snapshot.data()?["annualProMembershipCredits"] as? Int ?? 0
                guard credits > 0 else { return false }

                // One year from the moment this credit is spent — the
                // literal "1 year from the date of activation" instruction
                // this was built to. Deliberately doesn't stack with/extend
                // an already-active membership; revisit once a real
                // purchase path for this product exists alongside credits
                // (see the #4 plan).
                let newExpiresAt = Date.now.addingTimeInterval(365 * 24 * 60 * 60)
                transaction.setData([
                    "annualProMembershipCredits": credits - 1,
                    "annualProMembershipExpiresAt": Timestamp(date: newExpiresAt),
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
