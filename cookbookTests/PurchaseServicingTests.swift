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

    /// StoreKitPurchaseService.purchasableProduct(from:)'s real .autoRenewable
    /// mapping needs a live StoreKit `Product` and isn't unit-testable here —
    /// FakePurchaseService deliberately doesn't import StoreKit at all. This
    /// covers everything above that seam: the DTO/coordinator plumbing
    /// behaves identically for an auto-renewable product as for the existing
    /// kinds. The mapping itself is verified manually via Configuration.storekit
    /// in the Simulator.
    @Test func autoRenewableProductPurchasesAndSubmitsAClaimLikeAnyOtherKind() async throws {
        let service = FakePurchaseService()
        service.stubbedProducts = [makeProduct(id: StoreProductID.annualProMembership, kind: .autoRenewable)]
        let receipt = PurchaseReceipt(transactionID: "t1", productID: StoreProductID.annualProMembership, jwsRepresentation: "jws")
        service.outcomeForProductID[StoreProductID.annualProMembership] = .success(receipt)

        let products = try await service.fetchProducts()
        #expect(products.first?.kind == .autoRenewable)

        let outcome = try await service.purchase(productID: StoreProductID.annualProMembership)
        #expect(outcome == .success(receipt))
        #expect(await service.currentEntitlementProductIDs() == [StoreProductID.annualProMembership])
    }

    /// Backs MembershipPaywallView.restore(): what it resubmits claims from.
    @Test func currentEntitlementReceiptsReturnsWhateverIsStubbed() async throws {
        let service = FakePurchaseService()
        let receipt = PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws")
        service.stubbedCurrentEntitlementReceipts = [receipt]

        #expect(await service.currentEntitlementReceipts() == [receipt])
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

    // MARK: - finish() ordering / reconciliation (real-money entitlement-loss fix)

    /// The transaction must only be marked finished once the claim actually
    /// lands — finishing first would tell StoreKit "never redeliver this,"
    /// silently losing a paid-for entitlement forever if the claim write
    /// then failed.
    @Test func successfulPurchaseFinishesTheTransactionOnlyAfterTheClaimIsSubmitted() async throws {
        let purchaseService = FakePurchaseService()
        let receipt = PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws")
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .success(receipt)
        let claimWriter = FakePurchaseClaimWriter()

        _ = try await PurchaseCoordinator.purchase(
            makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
        )

        #expect(claimWriter.submittedClaims.count == 1)
        #expect(purchaseService.finishedTransactionIDs == ["t1"])
    }

    /// The core of the fix: a claim write failure must not lose the
    /// purchase — the transaction stays unfinished (recoverable via
    /// reconcileUnfinishedTransactions), and a distinct error is thrown so
    /// the UI doesn't tell the user their purchase failed when Apple has
    /// already charged them.
    @Test func aFailedClaimSubmissionLeavesTheTransactionUnfinishedAndThrowsADistinctError() async throws {
        let purchaseService = FakePurchaseService()
        let receipt = PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws")
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .success(receipt)
        let claimWriter = FakePurchaseClaimWriter()
        claimWriter.submitError = URLError(.notConnectedToInternet)

        await #expect(throws: PurchaseServiceError.claimSubmissionFailed) {
            try await PurchaseCoordinator.purchase(
                makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
            )
        }
        #expect(purchaseService.finishedTransactionIDs.isEmpty)
        #expect(await purchaseService.unfinishedReceipts() == [receipt])
    }

    @Test func reconcileResubmitsAndFinishesEveryUnfinishedTransaction() async throws {
        let purchaseService = FakePurchaseService()
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .success(
            PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws1")
        )
        let claimWriter = FakePurchaseClaimWriter()
        claimWriter.submitError = URLError(.notConnectedToInternet)
        await #expect(throws: PurchaseServiceError.claimSubmissionFailed) {
            try await PurchaseCoordinator.purchase(
                makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
            )
        }
        #expect(await purchaseService.unfinishedReceipts().count == 1)

        claimWriter.submitError = nil
        await PurchaseCoordinator.reconcileUnfinishedTransactions(
            userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
        )

        #expect(claimWriter.submittedClaims.count == 1)
        #expect(purchaseService.finishedTransactionIDs == ["t1"])
        #expect(await purchaseService.unfinishedReceipts().isEmpty)
    }

    @Test func reconcileLeavesAStillFailingTransactionUnfinishedRatherThanThrowing() async throws {
        let purchaseService = FakePurchaseService()
        purchaseService.outcomeForProductID[StoreProductID.proUserLifetime] = .success(
            PurchaseReceipt(transactionID: "t1", productID: StoreProductID.proUserLifetime, jwsRepresentation: "jws1")
        )
        let claimWriter = FakePurchaseClaimWriter()
        claimWriter.submitError = URLError(.notConnectedToInternet)
        await #expect(throws: PurchaseServiceError.claimSubmissionFailed) {
            try await PurchaseCoordinator.purchase(
                makeProduct(), userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
            )
        }

        // Still offline — reconcile must not crash/throw, just leave it for next time.
        await PurchaseCoordinator.reconcileUnfinishedTransactions(
            userID: "alice", purchaseService: purchaseService, claimWriter: claimWriter
        )

        #expect(purchaseService.finishedTransactionIDs.isEmpty)
        #expect(await purchaseService.unfinishedReceipts().count == 1)
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
