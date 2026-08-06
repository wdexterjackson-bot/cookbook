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
    /// Returns whether the caller should offer the free Family User promo
    /// credit redemption prompt — true only for a brand-new, promo-eligible
    /// account that was actually granted a credit just now.
    @discardableResult
    static func handle(_ result: AuthResult, modelContext: ModelContext, entitlementGranter: EntitlementGranting) async -> Bool {
        RecipeOwnershipMigrator.migrateGuestRecipesIfNeeded(in: modelContext, to: result.userID)
        CookbookMigrator.migrateGuestCookbooksIfNeeded(in: modelContext, to: result.userID)

        guard result.isNewAccount, PromoCredit.isEligible(on: .now) else { return false }
        do {
            try await entitlementGranter.grantPromoCreditsIfEligible(userID: result.userID)
            return true
        } catch {
            return false
        }
    }
}
