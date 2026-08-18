//
//  StoreKitPurchaseService.swift
//  cookbook
//
//  Real adapter over StoreKit 2. A verified purchase never writes the
//  entitlement itself — see PurchaseServicing.swift for why — it just
//  hands back the signed receipt for the caller to submit via
//  PurchaseClaimWriter.
//

import Foundation
import StoreKit

final class StoreKitPurchaseService: PurchaseServicing {
    func fetchProducts() async throws -> [PurchasableProduct] {
        let products = try await Product.products(for: StoreProductID.all)
        return products.map(Self.purchasableProduct(from:))
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        let products = try await Product.products(for: [productID])
        guard let product = products.first else {
            throw PurchaseServiceError.productNotFound
        }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw PurchaseServiceError.verificationFailed
            }
            let receipt = PurchaseReceipt(
                transactionID: String(transaction.id),
                productID: transaction.productID,
                jwsRepresentation: verification.jwsRepresentation
            )
            // Deliberately NOT calling transaction.finish() here — finishing
            // tells StoreKit "fully processed, never redeliver this," but
            // the purchaseClaims doc (what actually grants the entitlement)
            // hasn't been submitted yet at this point; that's the caller's
            // job (PurchaseCoordinator.purchase). Finishing before that
            // write is confirmed would silently lose a paid-for entitlement
            // forever if the write then failed (offline, app killed).
            return .success(receipt)
        case .pending:
            return .pending
        case .userCancelled:
            return .userCancelled
        @unknown default:
            return .pending
        }
    }

    func restorePurchases() async throws {
        try await AppStore.sync()
    }

    func currentEntitlementProductIDs() async -> Set<String> {
        var productIDs: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                productIDs.insert(transaction.productID)
            }
        }
        return productIDs
    }

    func currentEntitlementReceipts() async -> [PurchaseReceipt] {
        var receipts: [PurchaseReceipt] = []
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            receipts.append(PurchaseReceipt(
                transactionID: String(transaction.id),
                productID: transaction.productID,
                jwsRepresentation: result.jwsRepresentation
            ))
        }
        return receipts
    }

    func unfinishedReceipts() async -> [PurchaseReceipt] {
        var receipts: [PurchaseReceipt] = []
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            receipts.append(PurchaseReceipt(
                transactionID: String(transaction.id),
                productID: transaction.productID,
                jwsRepresentation: result.jwsRepresentation
            ))
        }
        return receipts
    }

    func finishTransaction(transactionID: String) async {
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result, String(transaction.id) == transactionID else { continue }
            await transaction.finish()
            return
        }
    }

    private static func purchasableProduct(from product: Product) -> PurchasableProduct {
        let kind: PurchaseKind
        switch product.type {
        case .nonConsumable:
            kind = .nonConsumable
        case .autoRenewable:
            kind = .autoRenewable
        default:
            kind = .consumable
        }
        return PurchasableProduct(
            id: product.id,
            displayName: product.displayName,
            description: product.description,
            displayPrice: product.displayPrice,
            kind: kind
        )
    }
}
