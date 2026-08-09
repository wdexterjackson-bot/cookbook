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
    /// Throws on a genuine fetch/save failure rather than silently
    /// returning an in-memory Cookbook that was never actually persisted —
    /// this runs on every launch and is what creates a brand-new account's
    /// very first Personal Cookbook, so a swallowed failure here could
    /// leave the app looking like it has a cookbook when the database
    /// doesn't actually agree.
    @discardableResult
    static func ensureDefaultCookbookExists(in context: ModelContext, ownerID: String) throws -> Cookbook {
        let descriptor = FetchDescriptor<Cookbook>(
            predicate: #Predicate { $0.ownerID == ownerID },
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        let existingCookbooks = try context.fetch(descriptor)

        let defaultCookbook: Cookbook
        if let first = existingCookbooks.first {
            defaultCookbook = first
        } else {
            let newCookbook = Cookbook(ownerID: ownerID, title: "Personal Cookbook", sortOrder: 0)
            context.insert(newCookbook)
            // Brand new, so it can't hold any pre-migration ingredient
            // text — mark it standardized now rather than letting
            // RootTabView's first-launch prompt fire for a cookbook with
            // nothing to standardize.
            RecipeStandardizationState.markStandardized(newCookbook.id)
            defaultCookbook = newCookbook
        }

        let recipeDescriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.ownerID == ownerID })
        let recipes = try context.fetch(recipeDescriptor)
        let defaultCookbookID = defaultCookbook.id
        for recipe in recipes where recipe.cookbookID == nil {
            recipe.cookbookID = defaultCookbookID
        }

        try context.save()
        return defaultCookbook
    }

    /// Companion to RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded —
    /// when a guest signs in, their Cookbooks (not just their recipes) need
    /// to move from the local guest identity to the new account, or a
    /// second person signing in later on the same device would see the
    /// first person's cookbooks too. Throws for the same reason
    /// RecipeOwnershipMigrator does — a silent failure here would strand
    /// the guest's cookbooks under the old device-local identity.
    static func migrateGuestCookbooksIfNeeded(in context: ModelContext, to newOwnerID: String) throws {
        let guestOwnerID = LocalOwner.id
        guard newOwnerID != guestOwnerID else { return }

        let descriptor = FetchDescriptor<Cookbook>(predicate: #Predicate { $0.ownerID == guestOwnerID })
        let guestCookbooks = try context.fetch(descriptor)
        guard !guestCookbooks.isEmpty else { return }

        for cookbook in guestCookbooks {
            cookbook.ownerID = newOwnerID
            cookbook.updatedAt = .now
        }
        try context.save()
    }
}
