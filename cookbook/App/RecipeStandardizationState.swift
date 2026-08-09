//
//  RecipeStandardizationState.swift
//  cookbook
//
//  Tracks which personal cookbooks have had RecipeQuantityStandardizer run
//  against them — keyed by cookbook (not owner), since "Standardize
//  Recipes" in the Administrator tab runs per-cookbook and completing it
//  there should stop RootTabView's first-launch prompt from nagging about
//  that same cookbook. Deliberately no permanent "don't ask again": the
//  first-launch prompt is meant to re-appear on every launch until a
//  cookbook is actually standardized (confirmed decision), so this only
//  ever records genuine completions, never a skip/dismissal.
//

import Foundation

enum RecipeStandardizationState {
    private static let defaultsKey = "com.vibeapp.cookbook.standardizedCookbookIDs"

    static func hasStandardized(_ cookbookID: UUID, defaults: UserDefaults = .standard) -> Bool {
        standardizedIDs(defaults: defaults).contains(cookbookID.uuidString)
    }

    static func markStandardized(_ cookbookID: UUID, defaults: UserDefaults = .standard) {
        var ids = standardizedIDs(defaults: defaults)
        ids.insert(cookbookID.uuidString)
        defaults.set(Array(ids), forKey: defaultsKey)
    }

    private static func standardizedIDs(defaults: UserDefaults) -> Set<String> {
        Set(defaults.stringArray(forKey: defaultsKey) ?? [])
    }
}
