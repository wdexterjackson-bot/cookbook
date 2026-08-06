//
//  ShoppingCartView.swift
//  cookbook
//
//  Grouped by source recipe, in the order each group was first added.
//  Editing is inline (a TextField bound directly to the SwiftData object,
//  since CartItem is a reference type) rather than a separate edit sheet,
//  matching the spec's "tapping an item's text opens it for inline
//  editing." Deliberately edits displayText only — that's the single
//  field actually shown to the user everywhere else in this app
//  (Ingredient.displayText follows the same "one authoritative string,
//  quantity/unit are best-effort extras" shape).
//

import SwiftUI
import SwiftData

private struct CartItemGroup: Identifiable {
    let id: String
    let title: String
    let items: [CartItem]
}

struct ShoppingCartView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var items: [CartItem]
    @State private var newItemText = ""
    @State private var isPresentingClearAllConfirmation = false

    init() {
        _items = Query(sort: \CartItem.createdAt)
    }

    private var ownedItems: [CartItem] {
        items.filter { $0.ownerID == accountState.currentOwnerID }
    }

    private var groups: [CartItemGroup] {
        var order: [String] = []
        var itemsByKey: [String: [CartItem]] = [:]
        var titleByKey: [String: String] = [:]
        for item in ownedItems {
            let key = item.sourceRecipeID ?? "__manual__"
            if itemsByKey[key] == nil {
                order.append(key)
                itemsByKey[key] = []
                titleByKey[key] = item.sourceRecipeTitleSnapshot ?? "Added by you"
            }
            itemsByKey[key]?.append(item)
        }
        return order.map { key in CartItemGroup(id: key, title: titleByKey[key] ?? "Added by you", items: itemsByKey[key] ?? []) }
    }

    private var checkedCount: Int {
        ownedItems.filter(\.checked).count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Add an item…", text: $newItemText)
                        .onSubmit(addManualItem)
                }

                if ownedItems.isEmpty {
                    ContentUnavailableView(
                        "Your Cart Is Empty",
                        systemImage: "cart",
                        description: Text("Add ingredients from any recipe to get started.")
                    )
                } else {
                    ForEach(groups) { group in
                        Section(group.title) {
                            ForEach(group.items) { item in
                                CartItemRow(item: item)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Shopping Cart")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !ownedItems.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if checkedCount > 0 {
                                Button("Clear Checked (\(checkedCount))") {
                                    CartItemStore.clearChecked(ownerID: accountState.currentOwnerID, in: modelContext)
                                }
                            }
                            Button("Clear All", role: .destructive) {
                                isPresentingClearAllConfirmation = true
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Cart actions")
                    }
                }
            }
            .confirmationDialog(
                "Clear \(ownedItems.count) item\(ownedItems.count == 1 ? "" : "s") from your cart?",
                isPresented: $isPresentingClearAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    CartItemStore.clearAll(ownerID: accountState.currentOwnerID, in: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func addManualItem() {
        let trimmed = newItemText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        CartItemStore.addManualItem(ownerID: accountState.currentOwnerID, displayText: trimmed, in: modelContext)
        newItemText = ""
    }
}

private struct CartItemRow: View {
    @Bindable var item: CartItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        HStack {
            Button {
                CartItemStore.setChecked(!item.checked, for: item, in: modelContext)
            } label: {
                Image(systemName: item.checked ? "checkmark.square.fill" : "square")
                    .foregroundStyle(item.checked ? Color.potluckSage : Color.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.checked ? "\(item.displayText), picked up" : "\(item.displayText), not yet picked up")

            TextField("Item", text: $item.displayText)
                .strikethrough(item.checked)
                .foregroundStyle(item.checked ? .secondary : .primary)

            Button(role: .destructive) {
                CartItemStore.remove(item, in: modelContext)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(item.displayText)")
        }
        .swipeActions {
            Button("Delete", role: .destructive) {
                CartItemStore.remove(item, in: modelContext)
            }
        }
    }
}

#Preview {
    ShoppingCartView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
