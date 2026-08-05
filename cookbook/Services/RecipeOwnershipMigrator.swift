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
    static func migrateGuestRecipesIfNeeded(in context: ModelContext, to newOwnerID: String) {
        let guestOwnerID = LocalOwner.id
        guard newOwnerID != guestOwnerID else { return }

        let descriptor = FetchDescriptor<Recipe>(
            predicate: #Predicate { $0.ownerID == guestOwnerID }
        )
        guard let guestRecipes = try? context.fetch(descriptor), !guestRecipes.isEmpty else { return }

        for recipe in guestRecipes {
            recipe.ownerID = newOwnerID
            recipe.updatedAt = .now
        }
        try? context.save()
    }
}
