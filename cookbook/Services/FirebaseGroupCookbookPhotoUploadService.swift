//
//  FirebaseGroupCookbookPhotoUploadService.swift
//  cookbook
//

import FirebaseStorage
import Foundation

final class FirebaseGroupCookbookPhotoUploadService: GroupCookbookPhotoUploadServicing {
    private let storage = Storage.storage()

    func upload(imageData: Data, groupID: String, cookbookID: String) async throws -> URL {
        let ref = storage.reference(withPath: Self.path(groupID: groupID, cookbookID: cookbookID))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        _ = try await ref.putDataAsync(imageData, metadata: metadata)
        return try await ref.downloadURL()
    }

    func delete(groupID: String, cookbookID: String) async throws {
        let ref = storage.reference(withPath: Self.path(groupID: groupID, cookbookID: cookbookID))
        try await ref.delete()
    }

    /// Matches storage.rules' `groupCookbookCovers/{groupID}/{cookbookID}/{fileName}` shape.
    private static func path(groupID: String, cookbookID: String) -> String {
        "groupCookbookCovers/\(groupID)/\(cookbookID)/cover.jpg"
    }
}
