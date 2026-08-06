//
//  InMemoryUserProfileService.swift
//  cookbook
//

import Foundation

final class InMemoryUserProfileService: UserProfileServicing {
    var locationsByUserID: [String: UserLocation] = [:]

    func fetchLocation(userID: String) async throws -> UserLocation? {
        locationsByUserID[userID]
    }

    func setLocation(_ location: UserLocation, userID: String) async throws {
        locationsByUserID[userID] = location
    }

    func deleteProfile(userID: String) async throws {
        locationsByUserID.removeValue(forKey: userID)
    }
}
