//
//  CartItemStore.swift
//  cookbook
//
//  Plain static helpers over CartItem, same weight as CookbookMigrator —
//  Cookbook/CartItem don't get a full protocol+adapter seam the way
//  Recipe does (RecipeStoring); there's no external dependency to fake
//  here, just SwiftData, so the extra layer isn't earning its keep.
//

import Foundation
import SwiftData

enum CartItemStore {
    /// "Second add [from the same recipe] is a no-op with the button
    /// already in its 'added' state — not a duplicate row." Matches on
    /// (owner, source recipe, display text) — manually-added items
    /// (sourceRecipeID == nil) are never deduped against each other.
    static func isInCart(ownerID: String, sourceRecipeID: String, displayText: String, in context: ModelContext) -> Bool {
        existingItem(ownerID: ownerID, sourceRecipeID: sourceRecipeID, displayText: displayText, in: context) != nil
    }

    @discardableResult
    static func addFromRecipe(
        ownerID: String,
        displayText: String,
        quantityValue: Double?,
        unit: String?,
        sourceRecipeID: String,
        sourceRecipeTitleSnapshot: String,
        in context: ModelContext
    ) throws -> CartItem {
        if let existing = existingItem(ownerID: ownerID, sourceRecipeID: sourceRecipeID, displayText: displayText, in: context) {
            return existing
        }
        let item = CartItem(
            ownerID: ownerID,
            displayText: displayText,
            quantityValue: quantityValue,
            unit: unit,
            sourceRecipeID: sourceRecipeID,
            sourceRecipeTitleSnapshot: sourceRecipeTitleSnapshot
        )
        context.insert(item)
        try context.save()
        return item
    }

    @discardableResult
    static func addManualItem(ownerID: String, displayText: String, in context: ModelContext) throws -> CartItem {
        let item = CartItem(ownerID: ownerID, displayText: displayText)
        context.insert(item)
        try context.save()
        return item
    }

    static func setChecked(_ checked: Bool, for item: CartItem, in context: ModelContext) throws {
        item.checked = checked
        try context.save()
    }

    static func remove(_ item: CartItem, in context: ModelContext) throws {
        context.delete(item)
        try context.save()
    }

    /// Returns how many items were removed, so the caller can show "Clear
    /// N items?" per the spec's confirmation requirement.
    @discardableResult
    static func clearAll(ownerID: String, in context: ModelContext) throws -> Int {
        let items = fetchAll(ownerID: ownerID, in: context)
        for item in items {
            context.delete(item)
        }
        try context.save()
        return items.count
    }

    @discardableResult
    static func clearChecked(ownerID: String, in context: ModelContext) throws -> Int {
        let items = fetchAll(ownerID: ownerID, in: context).filter(\.checked)
        for item in items {
            context.delete(item)
        }
        try context.save()
        return items.count
    }

    static func fetchAll(ownerID: String, in context: ModelContext) -> [CartItem] {
        let descriptor = FetchDescriptor<CartItem>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private static func existingItem(ownerID: String, sourceRecipeID: String, displayText: String, in context: ModelContext) -> CartItem? {
        let descriptor = FetchDescriptor<CartItem>(
            predicate: #Predicate { item in
                item.ownerID == ownerID && item.sourceRecipeID == sourceRecipeID && item.displayText == displayText
            }
        )
        return (try? context.fetch(descriptor))?.first
    }
}
