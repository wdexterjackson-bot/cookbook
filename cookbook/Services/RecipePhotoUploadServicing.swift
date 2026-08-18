//
//  RecipePhotoUploadServicing.swift
//  cookbook
//
//  The seam for the one Firebase Storage use case this app has: a
//  recipe's own photo traveling with it into a Family Cookbook.
//  Deliberately narrow — this is not a general-purpose upload service.
//

import Foundation

protocol RecipePhotoUploadServicing {
    /// Uploads to a deterministic path (groupID + cookbookID + ownerUserID
    /// + sourceRecipeID) so republishing overwrites the same file rather
    /// than accumulating orphans, and returns its download URL.
    /// cookbookID is part of the path (not just the Firestore doc) since a
    /// group can hold several cookbooks now — the same recipe published to
    /// two different cookbooks in the same group needs two distinct files.
    func upload(imageData: Data, groupID: String, cookbookID: String, ownerUserID: String, sourceRecipeID: String) async throws -> URL
    /// Best-effort cleanup on unpublish — callers should treat failure here
    /// as non-fatal (an orphaned Storage file is a minor cost, not worth
    /// blocking the unpublish the user actually asked for).
    func delete(groupID: String, cookbookID: String, ownerUserID: String, sourceRecipeID: String) async throws
}
