//
//  StorageMode.swift
//  cookbook
//
//  Whether a Cookbook's data lives only on this device, or is also pushed
//  to Firestore/Storage via the Personal Cookbook Cloud Sync feature
//  (2026-08-08). Was originally a single app-wide placeholder
//  (`static let current: StorageMode = .local`) documented as "Phase 2
//  turns this into a real user setting" — this is that Phase 2, except the
//  setting turned out to belong per-Cookbook (see CookbookConfigurationView's
//  "Sync to Cloud" toggle), not globally, since the user explicitly wants
//  to choose it per cookbook rather than for the whole account at once.
//
//  Stored directly as a Cookbook property, same pattern as
//  Recipe.sourceType: RecipeSourceType (a Codable enum SwiftData persists
//  natively, no separate Bool/String plumbing needed).
//

import Foundation

enum StorageMode: String, Codable {
    case local
    case cloudSynced
}
