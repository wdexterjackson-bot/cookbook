//
//  FakePersonalCookbookPhotoUploadService.swift
//  cookbook
//

import Foundation

final class FakePersonalCookbookPhotoUploadService: PersonalCookbookPhotoUploadServicing {
    private(set) var uploadedFileKeys: [String] = []
    private(set) var deletedFileKeys: [String] = []
    var stubbedError: Error?

    func upload(imageData: Data, ownerUserID: String, fileKey: String) async throws -> URL {
        if let stubbedError { throw stubbedError }
        uploadedFileKeys.append(fileKey)
        return URL(string: "https://example.com/personalCookbooks/\(ownerUserID)/\(fileKey).jpg")!
    }

    func delete(ownerUserID: String, fileKey: String) async throws {
        if let stubbedError { throw stubbedError }
        deletedFileKeys.append(fileKey)
    }
}
