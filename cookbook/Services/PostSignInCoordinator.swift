//
//  PostSignInCoordinator.swift
//  cookbook
//
//  Ties together the two side effects that must happen right after a
//  successful sign-in/sign-up: claiming any local guest recipes, and (for
//  brand-new accounts only) granting the sign-up promo credits.
//

import Foundation
import SwiftData

enum PostSignInCoordinator {
    static func handle(_ result: AuthResult, modelContext: ModelContext, entitlementGranter: EntitlementGranting) async {
        RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: modelContext, to: result.userID)

        if result.isNewAccount {
            try? await entitlementGranter.grantPromoCreditsIfEligible(userID: result.userID)
        }
    }
}
