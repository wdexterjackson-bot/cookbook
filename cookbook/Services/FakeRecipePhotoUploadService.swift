//
//  FakeRecipePhotoUploadService.swift
//  cookbook
//

import Foundation

final class FakeRecipePhotoUploadService: RecipePhotoUploadServicing {
    var uploadError: Error?
    private(set) var uploadedData: [String: Data] = [:]

    func upload(imageData: Data, groupID: String, ownerUserID: String, sourceRecipeID: String) async throws -> URL {
        if let uploadError { throw uploadError }
        let key = Self.key(groupID: groupID, ownerUserID: ownerUserID, sourceRecipeID: sourceRecipeID)
        uploadedData[key] = imageData
        return URL(string: "https://example.com/fake-storage/\(key).jpg")!
    }

    func delete(groupID: String, ownerUserID: String, sourceRecipeID: String) async throws {
        uploadedData.removeValue(forKey: Self.key(groupID: groupID, ownerUserID: ownerUserID, sourceRecipeID: sourceRecipeID))
    }

    private static func key(groupID: String, ownerUserID: String, sourceRecipeID: String) -> String {
        "\(groupID)/\(ownerUserID)_\(sourceRecipeID)"
    }
}
