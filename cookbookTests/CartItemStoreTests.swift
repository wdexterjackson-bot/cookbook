//
//  CartItemStoreTests.swift
//  cookbookTests
//

import Foundation
import SwiftData
import Testing
@testable import cookbook

struct CartItemStoreTests {

    private func makeInMemoryContext() throws -> ModelContext {
        let schema = Schema([
            Recipe.self, IngredientSection.self, Ingredient.self, StepSection.self, Step.self,
            Cookbook.self, CookbookSection.self, CartItem.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    @Test func addFromRecipeInsertsANewItem() throws {
        let context = try makeInMemoryContext()

        let item = CartItemStore.addFromRecipe(
            ownerID: "alice",
            displayText: "2 lb ground beef",
            quantityValue: 2,
            unit: "lb",
            sourceRecipeID: "recipe-1",
            sourceRecipeTitleSnapshot: "Sunday Gravy",
            in: context
        )

        #expect(item.displayText == "2 lb ground beef")
        #expect(item.checked == false)
        #expect(CartItemStore.fetchAll(ownerID: "alice", in: context).count == 1)
    }

    @Test func addingTheSameIngredientFromTheSameRecipeTwiceIsANoOp() throws {
        let context = try makeInMemoryContext()

        let first = CartItemStore.addFromRecipe(
            ownerID: "alice", displayText: "2 lb ground beef", quantityValue: 2, unit: "lb",
            sourceRecipeID: "recipe-1", sourceRecipeTitleSnapshot: "Sunday Gravy", in: context
        )
        let second = CartItemStore.addFromRecipe(
            ownerID: "alice", displayText: "2 lb ground beef", quantityValue: 2, unit: "lb",
            sourceRecipeID: "recipe-1", sourceRecipeTitleSnapshot: "Sunday Gravy", in: context
        )

        #expect(first.id == second.id)
        #expect(CartItemStore.fetchAll(ownerID: "alice", in: context).count == 1)
    }

    @Test func sameIngredientTextFromDifferentRecipesAreSeparateRows() throws {
        let context = try makeInMemoryContext()

        CartItemStore.addFromRecipe(ownerID: "alice", displayText: "2 lb ground beef", quantityValue: 2, unit: "lb", sourceRecipeID: "recipe-1", sourceRecipeTitleSnapshot: "Sunday Gravy", in: context)
        CartItemStore.addFromRecipe(ownerID: "alice", displayText: "2 lb ground beef", quantityValue: 2, unit: "lb", sourceRecipeID: "recipe-2", sourceRecipeTitleSnapshot: "Tacos", in: context)

        #expect(CartItemStore.fetchAll(ownerID: "alice", in: context).count == 2)
    }

    @Test func isInCartReflectsExistingItems() throws {
        let context = try makeInMemoryContext()
        #expect(CartItemStore.isInCart(ownerID: "alice", sourceRecipeID: "recipe-1", displayText: "Salt", in: context) == false)

        CartItemStore.addFromRecipe(ownerID: "alice", displayText: "Salt", quantityValue: nil, unit: nil, sourceRecipeID: "recipe-1", sourceRecipeTitleSnapshot: "Sunday Gravy", in: context)

        #expect(CartItemStore.isInCart(ownerID: "alice", sourceRecipeID: "recipe-1", displayText: "Salt", in: context) == true)
    }

    @Test func addManualItemAlwaysInsertsANewRow() throws {
        let context = try makeInMemoryContext()

        CartItemStore.addManualItem(ownerID: "alice", displayText: "Paper towels", in: context)
        CartItemStore.addManualItem(ownerID: "alice", displayText: "Paper towels", in: context)

        let items = CartItemStore.fetchAll(ownerID: "alice", in: context)
        #expect(items.count == 2)
        #expect(items.allSatisfy { $0.sourceRecipeID == nil })
    }

    @Test func setCheckedTogglesTheFlag() throws {
        let context = try makeInMemoryContext()
        let item = CartItemStore.addManualItem(ownerID: "alice", displayText: "Milk", in: context)

        CartItemStore.setChecked(true, for: item, in: context)
        #expect(item.checked == true)

        CartItemStore.setChecked(false, for: item, in: context)
        #expect(item.checked == false)
    }

    @Test func removeDeletesTheItem() throws {
        let context = try makeInMemoryContext()
        let item = CartItemStore.addManualItem(ownerID: "alice", displayText: "Milk", in: context)

        CartItemStore.remove(item, in: context)

        #expect(CartItemStore.fetchAll(ownerID: "alice", in: context).isEmpty)
    }

    @Test func clearAllRemovesEverythingForThatOwnerOnly() throws {
        let context = try makeInMemoryContext()
        CartItemStore.addManualItem(ownerID: "alice", displayText: "Milk", in: context)
        CartItemStore.addManualItem(ownerID: "alice", displayText: "Eggs", in: context)
        CartItemStore.addManualItem(ownerID: "bob", displayText: "Bread", in: context)

        let removedCount = CartItemStore.clearAll(ownerID: "alice", in: context)

        #expect(removedCount == 2)
        #expect(CartItemStore.fetchAll(ownerID: "alice", in: context).isEmpty)
        #expect(CartItemStore.fetchAll(ownerID: "bob", in: context).count == 1)
    }

    @Test func clearCheckedOnlyRemovesCheckedItems() throws {
        let context = try makeInMemoryContext()
        let milk = CartItemStore.addManualItem(ownerID: "alice", displayText: "Milk", in: context)
        CartItemStore.addManualItem(ownerID: "alice", displayText: "Eggs", in: context)
        CartItemStore.setChecked(true, for: milk, in: context)

        let removedCount = CartItemStore.clearChecked(ownerID: "alice", in: context)

        #expect(removedCount == 1)
        let remaining = CartItemStore.fetchAll(ownerID: "alice", in: context)
        #expect(remaining.count == 1)
        #expect(remaining.first?.displayText == "Eggs")
    }

    @Test func fetchAllIsSortedByCreationOrder() throws {
        let context = try makeInMemoryContext()
        CartItemStore.addManualItem(ownerID: "alice", displayText: "First", in: context)
        CartItemStore.addManualItem(ownerID: "alice", displayText: "Second", in: context)

        let items = CartItemStore.fetchAll(ownerID: "alice", in: context)

        #expect(items.map(\.displayText) == ["First", "Second"])
    }
}
