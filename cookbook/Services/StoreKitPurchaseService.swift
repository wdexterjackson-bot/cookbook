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
            await transaction.finish()
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
