//
//  GroupCookbookPhotoUploadServicing.swift
//  cookbook
//
//  Community Cookbook cover photo upload — same general seam shape as
//  PersonalCookbookPhotoUploadServicing, but keyed by groupID+cookbookID
//  (there's no single owner to scope by; visibility/write-access is
//  group-membership-based, same as publications/{groupID}/{cookbookID}
//  already is). One deterministic path per cookbook (not per-upload) so
//  replacing the cover overwrites the same file rather than accumulating
//  orphans.
//

import Foundation

protocol GroupCookbookPhotoUploadServicing {
    func upload(imageData: Data, groupID: String, cookbookID: String) async throws -> URL
    /// Best-effort cleanup — callers should treat failure here as
    /// non-fatal, same reasoning as RecipePhotoUploadServicing.delete.
    func delete(groupID: String, cookbookID: String) async throws
}
