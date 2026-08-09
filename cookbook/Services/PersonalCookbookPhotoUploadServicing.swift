//
//  PersonalCookbookPhotoUploadServicing.swift
//  cookbook
//
//  Personal Cookbook Cloud Sync's Storage seam — owner-scoped counterpart
//  to RecipePhotoUploadServicing (which is hard-coded to groups/publications
//  and not reusable here). `fileKey` becomes the filename under
//  personalCookbooks/{ownerUserID}/ (see storage.rules): a recipe's
//  `id.uuidString` for a recipe photo, or "cover_{cookbookID}" for a
//  cookbook's cover photo — one general seam instead of near-duplicate
//  upload/delete methods per photo kind.
//

import Foundation

protocol PersonalCookbookPhotoUploadServicing {
    /// Uploads to a deterministic path (ownerUserID + fileKey) so
    /// re-syncing overwrites the same file rather than accumulating
    /// orphans, and returns its download URL.
    func upload(imageData: Data, ownerUserID: String, fileKey: String) async throws -> URL
    /// Best-effort cleanup — callers should treat failure here as
    /// non-fatal, same reasoning as RecipePhotoUploadServicing.delete.
    func delete(ownerUserID: String, fileKey: String) async throws
}
