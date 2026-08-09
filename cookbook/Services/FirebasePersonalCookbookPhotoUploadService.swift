//
//  FirebasePersonalCookbookPhotoUploadService.swift
//  cookbook
//

import FirebaseStorage
import Foundation

final class FirebasePersonalCookbookPhotoUploadService: PersonalCookbookPhotoUploadServicing {
    private let storage = Storage.storage()

    func upload(imageData: Data, ownerUserID: String, fileKey: String) async throws -> URL {
        let ref = storage.reference(withPath: Self.path(ownerUserID: ownerUserID, fileKey: fileKey))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL()
    }

    func delete(ownerUserID: String, fileKey: String) async throws {
        let ref = storage.reference(withPath: Self.path(ownerUserID: ownerUserID, fileKey: fileKey))
        try await ref.delete()
    }

    /// Matches storage.rules' `personalCookbooks/{ownerUserID}/{fileName}` shape.
    private static func path(ownerUserID: String, fileKey: String) -> String {
        "personalCookbooks/\(ownerUserID)/\(fileKey).jpg"
    }
}
