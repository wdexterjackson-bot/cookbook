//
//  CookbookMigrator.swift
//  cookbook
//
//  Runs once at sign-in, same shape as RecipeOwnershipMigrator (2A).
//  Used to also auto-create a default "Personal Cookbook" for an owner
//  with none — removed (2026-08) in favor of the Home dashboard's
//  "Getting Started" card: a brand-new account now has zero cookbooks
//  until the user explicitly creates or restores one, and
//  CreateEditRecipeView's own save-time guard blocks adding a recipe
//  with nowhere to file it rather than silently orphaning it.
//

import Foundation
import SwiftData

enum CookbookMigrator {
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
