//
//  FakeGroupCookbookPhotoUploadService.swift
//  cookbook
//

import Foundation

final class FakeGroupCookbookPhotoUploadService: GroupCookbookPhotoUploadServicing {
    private(set) var uploadedCookbookIDs: [String] = []
    private(set) var deletedCookbookIDs: [String] = []
    var stubbedError: Error?

    func upload(imageData: Data, groupID: String, cookbookID: String) async throws -> URL {
        if let stubbedError { throw stubbedError }
        uploadedCookbookIDs.append(cookbookID)
        return URL(string: "https://example.com/groupCookbookCovers/\(groupID)/\(cookbookID)/cover.jpg")!
    }

    func delete(groupID: String, cookbookID: String) async throws {
        if let stubbedError { throw stubbedError }
        deletedCookbookIDs.append(cookbookID)
    }
}
