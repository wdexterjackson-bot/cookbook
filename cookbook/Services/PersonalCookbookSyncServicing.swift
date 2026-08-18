//
//  PersonalCookbookSyncServicing.swift
//  cookbook
//
//  Firestore-only seam for Personal Cookbook Cloud Sync — deliberately
//  knows nothing about SwiftData/ModelContext, matching GroupsServicing/
//  PublicationsServicing's own separation (local <-> remote reconciliation
//  is a coordinator's job, not this protocol's — see
//  PersonalCookbookSyncCoordinator). Takes/returns plain DTOs
//  (PersonalCookbookDoc/PersonalCookbookRecipeDoc), so FirestorePersonalCookbookSyncService
//  is the only conformer that needs to import Firestore at all.
//

import Foundation

enum PersonalCookbookSyncError: Error, Equatable {
    case notFound
    /// The remote cookbook doc's `updatedAt` no longer matches what this
    /// device last knew (`expectedRemoteUpdatedAt`) — another device
    /// pushed a change this device never pulled. Thrown instead of
    /// silently overwriting that other device's edits.
    case remoteChangedSinceLastSync
}

extension PersonalCookbookSyncError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notFound: return "That cookbook isn't synced to the cloud."
        case .remoteChangedSinceLastSync: return "This cookbook was updated on another device — pull the latest version before syncing again."
        }
    }
}

protocol PersonalCookbookSyncServicing {
    /// Writes the cookbook doc and every recipe subdoc as one atomic
    /// transaction — a partial sync (cookbook doc written, some recipes
    /// not, or vice versa) would be worse than the write simply failing
    /// outright. `expectedRemoteUpdatedAt` is this device's last known
    /// value of the remote doc's own `updatedAt` (nil if this cookbook
    /// has never been successfully synced before) — checked inside the
    /// same transaction before writing; a mismatch throws
    /// `.remoteChangedSinceLastSync` instead of proceeding.
    func push(_ cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc], expectedRemoteUpdatedAt: Date?) async throws

    /// Lightweight listing for the "Restore from Cloud" picker and the
    /// post-sign-in "cookbooks available on another device" prompt.
    func fetchSyncedCookbooks(forUser userID: String) async throws -> [PersonalCookbookSummary]

    /// Throws .notFound if no such cookbook doc exists (e.g. it was never
    /// pushed, or the id is wrong).
    func pull(cookbookID: UUID, ownerUserID: String) async throws -> (cookbook: PersonalCookbookDoc, recipes: [PersonalCookbookRecipeDoc])

    /// Deletes the cookbook doc and every recipe subdoc beneath it.
    /// Callers that also need the Storage photos cleaned up should use
    /// PersonalCookbookSyncCoordinator.deleteFromCloud, which calls this
    /// as its last step — this alone only removes the Firestore-side
    /// data. A no-op (not an error) if the cookbook was never synced.
    func delete(cookbookID: UUID, ownerUserID: String) async throws
}
