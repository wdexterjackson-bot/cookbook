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
                ToolbarItem(placement: .confirmationAction) {
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
            switch outcome {
            case .success:
                statusMessage = "Purchase complete — your membership will update shortly."
            case .pending:
                statusMessage = "Purchase pending approval."
            case .userCancelled:
                break
            }
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
            statusMessage = "Restored."
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
        PurchasableProduct(id: StoreProductID.familyCookbookCredit, displayName: "Create a Family Cookbook", description: "", displayPrice: "$1.99", kind: .consumable),
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
