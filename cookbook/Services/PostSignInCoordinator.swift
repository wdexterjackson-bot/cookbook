//
//  PostSignInCoordinator.swift
//  cookbook
//
//  Handles the one side effect that must happen right after a successful
//  sign-in/sign-up: claiming any local guest recipes/cookbooks. Free launch
//  credit granting used to live here (new accounts only) but now happens
//  unconditionally on every app launch instead — see AuthGatedRootView —
//  since it also needs to backfill existing accounts that predate a given
//  credit tier, not just brand-new ones.
//

import Foundation
import SwiftData

enum PostSignInCoordinator {
    static func handle(_ result: AuthResult, modelContext: ModelContext) throws {
        try RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: modelContext, to: result.userID)
        try CookbookMigrator.migrateGuestCookbooksIfNeeded(in: modelContext, to: result.userID)
    }
}
