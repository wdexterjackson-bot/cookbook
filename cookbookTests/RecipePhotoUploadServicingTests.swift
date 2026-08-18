//
//  RecipePhotoUploadServicingTests.swift
//  cookbookTests
//
//  Against the fake only — the real adapter needs live Firebase Storage,
//  same reasoning as every other Firebase-backed seam's test coverage.
//

import Foundation
import Testing
@testable import cookbook

struct RecipePhotoUploadServicingTests {

    @Test func uploadReturnsAURLAndDeleteRemovesTheStoredData() async throws {
        let service = FakeRecipePhotoUploadService()
        let data = Data([0xFF, 0xD8, 0xFF])

        let url = try await service.upload(imageData: data, groupID: "group-1", cookbookID: "cb-1", ownerUserID: "alice", sourceRecipeID: "recipe-1")

        #expect(url.absoluteString.contains("group-1"))
        #expect(service.uploadedData["group-1/cb-1/alice_recipe-1"] == data)

        try await service.delete(groupID: "group-1", cookbookID: "cb-1", ownerUserID: "alice", sourceRecipeID: "recipe-1")

        #expect(service.uploadedData["group-1/cb-1/alice_recipe-1"] == nil)
    }

    @Test func uploadThrowsWhenConfiguredToFail() async throws {
        let service = FakeRecipePhotoUploadService()
        service.uploadError = URLError(.notConnectedToInternet)

        await #expect(throws: URLError.self) {
            try await service.upload(imageData: Data(), groupID: "group-1", cookbookID: "cb-1", ownerUserID: "alice", sourceRecipeID: "recipe-1")
        }
    }

    @Test func differentCookbooksInTheSameGroupGetDistinctStorageKeys() async throws {
        let service = FakeRecipePhotoUploadService()
        let data = Data([0xFF, 0xD8, 0xFF])

        _ = try await service.upload(imageData: data, groupID: "group-1", cookbookID: "cb-1", ownerUserID: "alice", sourceRecipeID: "recipe-1")
        _ = try await service.upload(imageData: data, groupID: "group-1", cookbookID: "cb-2", ownerUserID: "alice", sourceRecipeID: "recipe-1")

        #expect(service.uploadedData["group-1/cb-1/alice_recipe-1"] == data)
        #expect(service.uploadedData["group-1/cb-2/alice_recipe-1"] == data)
    }
}
