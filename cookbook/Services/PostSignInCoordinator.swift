//
//  PostSignInCoordinator.swift
//  cookbook
//
//  Handles the side effects that must happen right after a successful
//  sign-in/sign-up: claiming any local guest recipes/cookbooks, and
//  syncing the account's email onto its userProfiles doc (what
//  findUserByEmail searches — see FEATURE 2's friend-discovery). Free
//  launch credit granting used to live here (new accounts only) but now
//  happens unconditionally on every app launch instead — see
//  AuthGatedRootView — since it also needs to backfill existing accounts
//  that predate a given credit tier, not just brand-new ones.
//

import Foundation
import SwiftData

enum PostSignInCoordinator {
    static func handle(
        _ result: AuthResult,
        email: String?,
        modelContext: ModelContext,
        userProfileService: UserProfileServicing = FirestoreUserProfileService()
    ) async throws {
        try RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: modelContext, to: result.userID)
        try CookbookMigrator.migrateGuestCookbooksIfNeeded(in: modelContext, to: result.userID)
        // Best-effort — a network hiccup here shouldn't block sign-in
        // itself; same reasoning as AccountDeletionCoordinator's own
        // best-effort entitlement/profile cleanup.
        if let email, !email.isEmpty {
            try? await userProfileService.setEmail(email, userID: result.userID)
        }
    }
}
