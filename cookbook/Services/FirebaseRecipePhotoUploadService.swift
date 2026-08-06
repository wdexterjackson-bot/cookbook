//
//  FirebaseRecipePhotoUploadService.swift
//  cookbook
//

import FirebaseStorage
import Foundation

final class FirebaseRecipePhotoUploadService: RecipePhotoUploadServicing {
    private let storage = Storage.storage()

    func upload(imageData: Data, groupID: String, ownerUserID: String, sourceRecipeID: String) async throws -> URL {
        let ref = storage.reference(withPath: Self.path(groupID: groupID, ownerUserID: ownerUserID, sourceRecipeID: sourceRecipeID))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL()
    }

    func delete(groupID: String, ownerUserID: String, sourceRecipeID: String) async throws {
        let ref = storage.reference(withPath: Self.path(groupID: groupID, ownerUserID: ownerUserID, sourceRecipeID: sourceRecipeID))
        try await ref.delete()
    }

    /// Matches storage.rules' `publications/{groupID}/{fileName}` shape,
    /// with fileName prefixed by the uploader's own uid — the write rule
    /// checks exactly that prefix.
    private static func path(groupID: String, ownerUserID: String, sourceRecipeID: String) -> String {
        "publications/\(groupID)/\(ownerUserID)_\(sourceRecipeID).jpg"
    }
}
