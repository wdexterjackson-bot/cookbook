//
//  CartItem.swift
//  cookbook
//
//  Shopping Cart spec (Aug 6, 2026) — a personal grocery list, cross-cookbook.
//  Local-first SwiftData model, same as Recipe/Cookbook (this app has no
//  cloud sync for personal data yet — "syncs like personal recipe edits"
//  per the spec means "local-only, scoped by ownerID," matching Recipe's
//  actual current architecture, not a new Firestore collection).
//
//  Deliberately NOT a lineage field: sourceRecipeID is a plain opaque
//  string (holds either a local Recipe's UUID string or a Firestore
//  Publication's String id — a cart item can come from either) purely for
//  grouping/display. No ownership or copy semantics attach to it, per the
//  spec's explicit distinction from "Copy to Personal."
//

import Foundation
import SwiftData

@Model
final class CartItem {
    var id: UUID
    var ownerID: String

    /// The author-entered ingredient string as shown to the user, editable
    /// in place. Never blocks saving if quantity/unit can't be parsed from
    /// it — same fallback principle as Ingredient.displayText (REC-004).
    var displayText: String
    var quantityValue: Double?
    var unit: String?

    /// Null for manually-added items ("Added by you" group).
    var sourceRecipeID: String?
    /// Captured at add-time so the group label still makes sense if the
    /// source recipe is later renamed, unpublished, or deleted.
    var sourceRecipeTitleSnapshot: String?
    /// The originating Ingredient's own stable id — identity for dedup
    /// ("already in cart?") purposes. Deliberately NOT displayText: this
    /// item's displayText is user-editable in the cart itself, so matching
    /// on text would let a rename desync the "already added" button on the
    /// recipe screen and let a re-tap insert a duplicate row.
    var sourceIngredientID: UUID?

    var checked: Bool
    var createdAt: Date

    init(
        ownerID: String,
        displayText: String,
        quantityValue: Double? = nil,
        unit: String? = nil,
        sourceRecipeID: String? = nil,
        sourceRecipeTitleSnapshot: String? = nil,
        sourceIngredientID: UUID? = nil
    ) {
        self.id = UUID()
        self.ownerID = ownerID
        self.displayText = displayText
        self.quantityValue = quantityValue
        self.unit = unit
        self.sourceRecipeID = sourceRecipeID
        self.sourceRecipeTitleSnapshot = sourceRecipeTitleSnapshot
        self.sourceIngredientID = sourceIngredientID
        self.checked = false
        self.createdAt = .now
    }
}
