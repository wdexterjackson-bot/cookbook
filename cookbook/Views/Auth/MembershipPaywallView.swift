//
//  MembershipPaywallView.swift
//  cookbook
//
//  Reachable from AccountView, and presented directly by EntitlementGate
//  whenever a create/join action has no credit left to spend. Shows current
//  entitlement status (Pro User, remaining tier-1/tier-2 credits) and lets
//  the user buy/restore, or redeem a tier-1 credit toward Pro User in place
//  of buying. A successful StoreKit purchase writes a purchaseClaims doc
//  (PurchaseClaimSubmitting) rather than the entitlement itself — see
//  PurchaseServicing.swift for why.
//

import SwiftUI

struct MembershipPaywallView: View {
    let userID: String
    let purchaseService: PurchaseServicing
    let claimWriter: PurchaseClaimSubmitting
    let entitlementService: EntitlementServicing
    /// Set only when this paywall was presented by EntitlementGate to
    /// unblock a specific pending action (e.g. creating a Community
    /// Cookbook) — nil when reached directly from Account, where there's
    /// nothing to resume.
    var onPurchaseSucceeded: (() async -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var entitlement: Entitlement?
    @State private var products: [PurchasableProduct] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Membership") {
                    MembershipSummaryView(entitlement: entitlement)
                }

                if (entitlement?.tier1Credits ?? 0) > 0, entitlement?.isProUser != true {
                    Section("Free Credit Available") {
                        Text("You have a Pro User credit available — redeem it to join and connect with unlimited family/friends' cookbooks, instead of buying.")
                            .foregroundStyle(.secondary)
                        Button("Redeem Credit for Pro User") {
                            Task { await redeemTier1Credit() }
                        }
                        .disabled(isBusy)
                    }
                }

                Section("Buy") {
                    ForEach(products) { product in
                        Button {
                            Task { await purchase(product) }
                        } label: {
                            LabeledContent(product.displayName, value: product.displayPrice)
                        }
                        .disabled(isBusy)
                    }
                }

                Button("Restore Purchases") {
                    Task { await restore() }
                }
                .disabled(isBusy)

                if isBusy {
                    ProgressView()
                }
                if let statusMessage {
                    Text(statusMessage).foregroundStyle(.green)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle("Membership")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await refresh()
            }
        }
    }

    private func refresh() async {
        async let entitlementFetch = try? entitlementService.fetchEntitlement(userID: userID)
        async let productsFetch = (try? purchaseService.fetchProducts()) ?? []
        entitlement = await entitlementFetch ?? nil
        products = await productsFetch
    }

    private func redeemTier1Credit() async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            let redeemed = try await entitlementService.redeemTier1CreditForProUser(userID: userID)
            if redeemed {
                statusMessage = "You're now a Pro User."
            } else {
                errorMessage = "That credit isn't available anymore."
            }
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purchase(_ product: PurchasableProduct) async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            let outcome = try await PurchaseCoordinator.purchase(
                product, userID: userID, purchaseService: purchaseService, claimWriter: claimWriter
            )
            var didSucceed = false
            switch outcome {
            case .success:
                statusMessage = "Purchase complete — your membership will update shortly."
                didSucceed = true
            case .pending:
                statusMessage = "Purchase pending approval."
            case .userCancelled:
                break
            }
            await refresh()
            if didSucceed, let onPurchaseSucceeded {
                await onPurchaseSucceeded()
            }
        } catch PurchaseServiceError.claimSubmissionFailed {
            // Apple has already been paid — this isn't a failed purchase,
            // just an unconfirmed one. PurchaseCoordinator.
            // reconcileUnfinishedTransactions (run at every launch) will
            // pick it up automatically; no action needed from the user.
            statusMessage = "Purchase completed but couldn't confirm right away — this will resolve automatically."
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restore() async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            try await purchaseService.restorePurchases()
            // Resubmitting a claim for everything StoreKit currently shows
            // as owned is safe even for an already-applied purchase —
            // applyPurchaseClaim.js is keyed by transaction ID and no-ops
            // on a repeat — so there's no need to first diff against the
            // server's entitlement doc here.
            let receipts = await purchaseService.currentEntitlementReceipts()
            var resubmittedCount = 0
            for receipt in receipts {
                do {
                    try await claimWriter.submit(receipt, userID: userID)
                    resubmittedCount += 1
                } catch {
                    continue
                }
            }
            statusMessage = resubmittedCount == 0
                ? "No purchases found for this account."
                : "Restored — checked \(resubmittedCount) purchase\(resubmittedCount == 1 ? "" : "s")."
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let purchaseService = FakePurchaseService()
    purchaseService.stubbedProducts = [
        PurchasableProduct(id: StoreProductID.proUserLifetime, displayName: "Pro User", description: "", displayPrice: "$0.99", kind: .nonConsumable),
        PurchasableProduct(id: StoreProductID.familyCookbookCredit, displayName: "Create a Community Cookbook", description: "", displayPrice: "$1.99", kind: .consumable),
    ]
    let entitlementService = InMemoryEntitlementService()
    entitlementService.entitlementsByUserID["preview-user"] = Entitlement(
        userID: "preview-user", tier1Credits: 1, tier2Credits: 2, isProUser: false,
        receivedTier1PromoCredit: true, receivedTier2PromoCredits: true, createdAt: .now
    )
    return MembershipPaywallView(
        userID: "preview-user",
        purchaseService: purchaseService,
        claimWriter: FakePurchaseClaimWriter(),
        entitlementService: entitlementService
    )
}
