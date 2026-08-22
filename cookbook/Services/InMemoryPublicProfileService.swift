//
//  InMemoryPublicProfileService.swift
//  cookbook
//

import Foundation

final class InMemoryPublicProfileService: PublicProfileServicing {
    private(set) var displayNamesByUserID: [String: String] = [:]

    func setDisplayName(_ displayName: String, userID: String) async throws {
        displayNamesByUserID[userID] = displayName
    }

    func fetchDisplayNames(userIDs: [String]) async throws -> [String: String] {
        var result: [String: String] = [:]
        for userID in userIDs {
            if let name = displayNamesByUserID[userID] {
                result[userID] = name
            }
        }
        return result
    }
}
