//
//  MembershipPaywallView.swift
//  cookbook
//
//  Milestone 2D — reachable from AccountView. Shows current entitlement
//  status (Family User, remaining creation credits, an unredeemed promo
//  credit if any) and lets the user buy/restore, or redeem their free
//  promo credit in place of buying. A successful StoreKit purchase writes
//  a purchaseClaims doc (PurchaseClaimSubmitting) rather than the
//  entitlement itself — see PurchaseServicing.swift for why.
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
                    LabeledContent("Family User", value: (entitlement?.hasFamilyUser ?? false) ? "Yes" : "No")
                    LabeledContent("Family Creation Credits", value: "\(entitlement?.creationCredits ?? 0)")
                }

                if entitlement?.familyUserPromoCreditAvailable == true {
                    Section("Free Credit Available") {
                        Text("You have a free Family User credit from signing up early. It never expires and isn't transferable to another account.")
                            .foregroundStyle(.secondary)
                        Button("Redeem Free Credit") {
                            Task { await redeemPromoCredit() }
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

    private func redeemPromoCredit() async {
        isBusy = true
        errorMessage = nil
        statusMessage = nil
        defer { isBusy = false }
        do {
            let redeemed = try await entitlementService.redeemFamilyUserPromoCredit(userID: userID)
            if redeemed {
                statusMessage = "You're now a Family User."
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
            let outcome = try await purchaseService.purchase(productID: product.id)
            switch outcome {
            case .success(let receipt):
                try await claimWriter.submit(receipt, userID: userID)
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
        PurchasableProduct(id: StoreProductID.familyUserLifetime, displayName: "Family User", description: "", displayPrice: "$0.99", kind: .nonConsumable),
        PurchasableProduct(id: StoreProductID.groupCreationCredit, displayName: "Create a Family", description: "", displayPrice: "$1.99", kind: .consumable),
    ]
    let entitlementService = InMemoryEntitlementService()
    entitlementService.entitlementsByUserID["preview-user"] = Entitlement(
        userID: "preview-user", creationCredits: 3, hasFamilyUser: false,
        familyUserPromoCreditAvailable: true, grantedPromoCredits: true, createdAt: .now
    )
    return MembershipPaywallView(
        userID: "preview-user",
        purchaseService: purchaseService,
        claimWriter: FakePurchaseClaimWriter(),
        entitlementService: entitlementService
    )
}
