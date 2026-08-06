//
//  PurchaseClaimWriter.swift
//  cookbook
//
//  Writes purchaseClaims/{transactionID} after a StoreKit-verified purchase.
//  This is deliberately not part of PurchaseServicing: that seam is
//  StoreKit-only and its fake has no reason to import Firestore. A Cloud
//  Function (Milestone 2D-4) reacts to this doc, independently re-verifies
//  the JWS against Apple, and only then grants the entitlement via the
//  Admin SDK — see firestore.rules' entitlements block for why the client
//  can never do that grant itself.
//

import FirebaseFirestore
import Foundation

protocol PurchaseClaimSubmitting {
    func submit(_ receipt: PurchaseReceipt, userID: String) async throws
}

final class FirestorePurchaseClaimWriter: PurchaseClaimSubmitting {
    private let db = Firestore.firestore()

    func submit(_ receipt: PurchaseReceipt, userID: String) async throws {
        try await db.collection("purchaseClaims").document(receipt.transactionID).setData([
            "userID": userID,
            "productID": receipt.productID,
            "transactionID": receipt.transactionID,
            "jwsRepresentation": receipt.jwsRepresentation,
            "submittedAt": FieldValue.serverTimestamp(),
        ], merge: true)
    }
}

final class FakePurchaseClaimWriter: PurchaseClaimSubmitting {
    private(set) var submittedClaims: [(receipt: PurchaseReceipt, userID: String)] = []

    func submit(_ receipt: PurchaseReceipt, userID: String) async throws {
        submittedClaims.append((receipt, userID))
    }
}
