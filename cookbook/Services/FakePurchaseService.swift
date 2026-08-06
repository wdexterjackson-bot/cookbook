//
//  FakePurchaseService.swift
//  cookbook
//
//  In-memory stand-in so tests never touch StoreKit. Configure
//  `stubbedProducts`/`outcomeForProductID`/`entitledProductIDs` before
//  exercising the code under test.
//

import Foundation

final class FakePurchaseService: PurchaseServicing {
    var stubbedProducts: [PurchasableProduct] = []
    var outcomeForProductID: [String: PurchaseOutcome] = [:]
    var entitledProductIDs: Set<String> = []
    var restoreCallCount = 0
    private(set) var purchasedProductIDs: [String] = []

    func fetchProducts() async throws -> [PurchasableProduct] {
        stubbedProducts
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        purchasedProductIDs.append(productID)
        guard let outcome = outcomeForProductID[productID] else {
            throw PurchaseServiceError.productNotFound
        }
        if case .success = outcome {
            entitledProductIDs.insert(productID)
        }
        return outcome
    }

    func restorePurchases() async throws {
        restoreCallCount += 1
    }

    func currentEntitlementProductIDs() async -> Set<String> {
        entitledProductIDs
    }
}
