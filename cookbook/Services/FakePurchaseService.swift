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
    /// Transactions `purchase(productID:)` returned `.success` for but
    /// `finishTransaction` hasn't been called on yet — mirrors StoreKit's
    /// own `Transaction.unfinishedTransactions` semantics closely enough
    /// for PurchaseCoordinator's reconcile logic to be tested against it.
    private(set) var unfinishedReceiptsByID: [String: PurchaseReceipt] = [:]
    private(set) var finishedTransactionIDs: [String] = []
    /// What `currentEntitlementReceipts()` returns — set this directly in
    /// a test to simulate "Restore Purchases" finding something the
    /// server's entitlement doc doesn't yet reflect (a different device's
    /// purchase, or one whose claim silently failed).
    var stubbedCurrentEntitlementReceipts: [PurchaseReceipt] = []

    func fetchProducts() async throws -> [PurchasableProduct] {
        stubbedProducts
    }

    func purchase(productID: String) async throws -> PurchaseOutcome {
        purchasedProductIDs.append(productID)
        guard let outcome = outcomeForProductID[productID] else {
            throw PurchaseServiceError.productNotFound
        }
        if case .success(let receipt) = outcome {
            entitledProductIDs.insert(productID)
            unfinishedReceiptsByID[receipt.transactionID] = receipt
        }
        return outcome
    }

    func restorePurchases() async throws {
        restoreCallCount += 1
    }

    func currentEntitlementProductIDs() async -> Set<String> {
        entitledProductIDs
    }

    func currentEntitlementReceipts() async -> [PurchaseReceipt] {
        stubbedCurrentEntitlementReceipts
    }

    func unfinishedReceipts() async -> [PurchaseReceipt] {
        Array(unfinishedReceiptsByID.values)
    }

    func finishTransaction(transactionID: String) async {
        finishedTransactionIDs.append(transactionID)
        unfinishedReceiptsByID.removeValue(forKey: transactionID)
    }
}
