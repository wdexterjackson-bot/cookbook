//
//  CookbookMigrator.swift
//  cookbook
//
//  Runs once at launch, same shape as RecipeOwnershipMigrator (2A): if the
//  current owner has no Cookbook yet, create a default one and backfill
//  any of their recipes that predate the Cookbook concept entirely (no
//  cookbookID set). Idempotent — safe to call on every launch.
//

import Foundation
import SwiftData

enum CookbookMigrator {
    @discardableResult
    static func ensureDefaultCookbookExists(in context: ModelContext, ownerID: String) -> Cookbook {
        let descriptor = FetchDescriptor<Cookbook>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let existingCookbooks = (try? context.fetch(descriptor)) ?? []

        let defaultCookbook: Cookbook
        if let first = existingCookbooks.first {
            defaultCookbook = first
        } else {
            let newCookbook = Cookbook(ownerID: ownerID, title: "Personal Cookbook", sortOrder: 0)
            context.insert(newCookbook)
            defaultCookbook = newCookbook
        }

        let recipeDescriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.ownerID == ownerID })
        let recipes = (try? context.fetch(recipeDescriptor)) ?? []
        let defaultCookbookID = defaultCookbook.id
        for recipe in recipes where recipe.cookbookID == nil {
            recipe.cookbookID = defaultCookbookID
        }

        try? context.save()
        return defaultCookbook
    }

    /// Companion to RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded —
    /// when a guest signs in, their Cookbooks (not just their recipes) need
    /// to move from the local guest identity to the new account, or a
    /// second person signing in later on the same device would see the
    /// first person's cookbooks too.
    static func migrateGuestCookbooksIfNeeded(in context: ModelContext, to newOwnerID: String) {
        let guestOwnerID = LocalOwner.id
        guard newOwnerID != guestOwnerID else { return }

        let descriptor = FetchDescriptor<Cookbook>(predicate: #Predicate { $0.ownerID == guestOwnerID })
        guard let guestCookbooks = try? context.fetch(descriptor), !guestCookbooks.isEmpty else { return }

        for cookbook in guestCookbooks {
            cookbook.ownerID = newOwnerID
            cookbook.updatedAt = .now
        }
        try? context.save()
    }
}
