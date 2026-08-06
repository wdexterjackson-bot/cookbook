//
//  AddToCartButton.swift
//  cookbook
//
//  Shared between Recipe Detail and Cooking Mode's ingredient list, per
//  the Shopping Cart spec. Uses a scoped @Query (not a one-time check) so
//  the outlined-vs-filled state stays live if the same ingredient gets
//  added from another screen in the same session.
//

import SwiftUI
import SwiftData

struct AddToCartButton: View {
    let ownerID: String
    let sourceRecipeID: String
    let sourceRecipeTitleSnapshot: String
    let displayText: String
    let quantityValue: Double?
    let unit: String?

    @Environment(\.modelContext) private var modelContext
    @Query private var matchingItems: [CartItem]

    init(
        ownerID: String,
        sourceRecipeID: String,
        sourceRecipeTitleSnapshot: String,
        displayText: String,
        quantityValue: Double?,
        unit: String?
    ) {
        self.ownerID = ownerID
        self.sourceRecipeID = sourceRecipeID
        self.sourceRecipeTitleSnapshot = sourceRecipeTitleSnapshot
        self.displayText = displayText
        self.quantityValue = quantityValue
        self.unit = unit
        _matchingItems = Query(filter: #Predicate<CartItem> { item in
            item.ownerID == ownerID && item.sourceRecipeID == sourceRecipeID && item.displayText == displayText
        })
    }

    private var isInCart: Bool { !matchingItems.isEmpty }

    var body: some View {
        Button {
            CartItemStore.addFromRecipe(
                ownerID: ownerID,
                displayText: displayText,
                quantityValue: quantityValue,
                unit: unit,
                sourceRecipeID: sourceRecipeID,
                sourceRecipeTitleSnapshot: sourceRecipeTitleSnapshot,
                in: modelContext
            )
        } label: {
            Image(systemName: isInCart ? "checkmark.circle.fill" : "cart.badge.plus")
                .foregroundStyle(isInCart ? Color.potluckSage : Color.potluckTomato)
        }
        .buttonStyle(.plain)
        .disabled(isInCart)
        .accessibilityLabel(isInCart ? "\(displayText), already added to cart" : "Add \(displayText) to cart")
    }
}

/// A brief, non-blocking confirmation — "Add all to cart" and per-item
/// adds both use this rather than an alert, per the spec ("a brief
/// confirmation toast... without blocking the list").
struct CartToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.potluckDeepTeal))
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension View {
    /// Shows `message` for a couple of seconds, bottom-aligned, then
    /// clears it automatically. Callers just set the bound message.
    func cartToast(_ message: Binding<String?>) -> some View {
        overlay(alignment: .bottom) {
            if let text = message.wrappedValue {
                CartToast(message: text)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: message.wrappedValue)
    }
}
