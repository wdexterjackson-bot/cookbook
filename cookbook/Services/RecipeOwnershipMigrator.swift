//
//  RecipeOwnershipMigrator.swift
//  cookbook
//
//  Runs once per device, the first time sign-in succeeds: reassigns any
//  recipes still owned by the local guest identity (LocalOwner.id) to the
//  newly-authenticated account. Without this, a shared device could mix one
//  person's recipes into another's list once a second person signs in
//  (the reference doc's "owner-key scoping" concern).
//

import Foundation
import SwiftData

enum RecipeOwnershipMigrator {
    /// Throws on a genuine fetch/save failure — a silent failure here would
    /// leave the guest's recipes stranded under the old device-local
    /// identity with no retry or indication anything went wrong, right
    /// after the user just signed in expecting their recipes to follow them.
    static func migrateGuestRecipesIfNeeded(in context: ModelContext, to newOwnerID: String) throws {
        let guestOwnerID = LocalOwner.id
        guard newOwnerID != guestOwnerID else { return }

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.ownerID == guestOwnerID }
        )
        let guestRecipes = try context.fetch(descriptor)
        guard !guestRecipes.isEmpty else { return }

        for recipe in guestRecipes {
            recipe.ownerID = newOwnerID
            recipe.updatedAt = .now
        }
        try context.save()
    }
}
