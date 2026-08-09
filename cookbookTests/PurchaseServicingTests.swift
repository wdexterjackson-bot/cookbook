//
//  PurchaseServicingTests.swift
//  cookbookTests
//
//  Covers the StoreKit purchase seam, previously untested despite being the
//  one path that moves real money — FakePurchaseService's contract, and
//  PurchaseCoordinator's purchase→claim-submission orchestration (extracted
//  from MembershipPaywallView specifically so it could be tested here).
//

import Foundation
import Testing
@testable import cookbook

struct PurchaseServicingTests {

    private func makeProduct(id: String = StoreProductID.proUserLifetime, kind: PurchaseKind = .nonConsumable) -> PurchasableProduct {
        PurchasableProduct(id: id, displayName: "Pro User", description: "", displayPrice: "$0.99", kind: kind)
    }

    // MARK: - FakePurchaseService contract

    @Test func fetchProductsReturnsWhateverIsStubbed() async throws {
        let service = FakePurchaseService()
        service.stubbedProducts = [makeProduct()]

        let products = try await service.fetchProducts()

        #expect(products.map(\.id) == [StoreProductID.proUserLifetime])
    }

    @Test func purchaseOfAnUnstubbedProductThrowsProductNotFound() async throws {
        let service = FakePurchaseService()

        await #expect(throws: PurchaseServiceError.productNotFound) {
            try await service.purchase(productID: StoreProductID.proUserLifetime)
        }
    }

    @Test func successfulPurchaseAddsToCurrentEntitlements() async throws {
        let service = FakePurchaseService()
        let receipt = PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws")
        service.outcomeForProductID[StoreProductID.proUserLifetime] = .success(receipt)

        let outcome = try await service.purchase(productID: StoreProductID.proUserLifetime)

        #expect(outcome == .success(receipt))
        #expect(await service.currentEntitlementProductIDs() == [StoreProductID.proUserLifetime])
        #expect(service.purchasedProductIDs == [StoreProductID.proUserLifetime])
    }

    @Test func pendingAndCancelledOutcomesDoNotGrantAnEntitlement() async throws {
        let service = FakePurchaseService()
        service.outcomeForProductID[StoreProductID.proUserLifetime] = .pending
        service.outcomeForProductID[StoreProductID.familyCookbookCredit] = .userCancelled

        _ = try await service.purchase(productID: StoreProductID.proUserLifetime)
        _ = try await service.purchase(productID: StoreProductID.familyCookbookCredit)

        #expect(await service.currentEntitlementProductIDs().isEmpty)
    }

    @Test func restorePurchasesTracksCallCount() async throws {
        let service = FakePurchaseService()

        try await service.restorePurchases()
        try await service.restorePurchases()

        #expect(service.restoreCallCount == 2)
    }

    // MARK: - PurchaseCoordinator (purchase -> claim submission)

    @Test func successfulPurchaseSubmitsExactlyOneClaim() async throws {
        let purchaseService = FakePurchaseService()
        let receipt = PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws")
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .success(receipt)
        let claimWriter = FakePurchaseClaimWriter()

        let outcome = try await PurchaseCoordinator.purchase(
            makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
        )

        #expect(outcome == .success(receipt))
        #expect(claimWriter.submittedClaims.count == 1)
        #expect(claimWriter.submittedClaims.first?.receipt == receipt)
        #expect(claimWriter.submittedClaims.first?.userID == "alice")
    }

    /// This is the invariant that actually matters: a pending StoreKit
    /// outcome (e.g. Ask to Buy) must never produce a purchaseClaims doc —
    /// there's no verified transaction yet for a Cloud Function to check.
    @Test func pendingOutcomeNeverSubmitsAClaim() async throws {
        let purchaseService = FakePurchaseService()
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .pending
        let claimWriter = FakePurchaseClaimWriter()

        let outcome = try await PurchaseCoordinator.purchase(
            makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
        )

        #expect(outcome == .pending)
        #expect(claimWriter.submittedClaims.isEmpty)
    }

    @Test func userCancelledNeverSubmitsAClaim() async throws {
        let purchaseService = FakePurchaseService()
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .userCancelled
        let claimWriter = FakePurchaseClaimWriter()

        let outcome = try await PurchaseCoordinator.purchase(
            makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
        )

        #expect(outcome == .userCancelled)
        #expect(claimWriter.submittedClaims.isEmpty)
    }

    @Test func aThrownPurchaseErrorNeverSubmitsAClaim() async throws {
        let purchaseService = FakePurchaseService()
        // No outcome stubbed for this product ID — purchase() throws .productNotFound.
        let claimWriter = FakePurchaseClaimWriter()

        await #expect(throws: PurchaseServiceError.self) {
            try await PurchaseCoordinator.purchase(
                makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
            )
        }
        #expect(claimWriter.submittedClaims.isEmpty)
    }
}
