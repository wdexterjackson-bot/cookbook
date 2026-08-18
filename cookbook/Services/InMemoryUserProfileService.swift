//
//  InMemoryUserProfileService.swift
//  cookbook
//

import Foundation

final class InMemoryUserProfileService: UserProfileServicing {
    var locationsByUserID: [String: UserLocation] = [:]
    var emailsByUserID: [String: String] = [:]
    var emailDiscoverableByUserID: [String: Bool] = [:]

    func fetchLocation(userID: String) async throws -> UserLocation? {
        locationsByUserID[userID]
    }

    func setLocation(_ location: UserLocation, userID: String) async throws {
        locationsByUserID[userID] = location
    }

    func setEmail(_ email: String, userID: String) async throws {
        emailsByUserID[userID] = email
    }

    func fetchIsEmailDiscoverable(userID: String) async throws -> Bool {
        emailDiscoverableByUserID[userID] ?? true
    }

    func setEmailDiscoverable(_ discoverable: Bool, userID: String) async throws {
        emailDiscoverableByUserID[userID] = discoverable
    }

    func deleteProfile(userID: String) async throws {
        locationsByUserID.removeValue(forKey: userID)
        emailsByUserID.removeValue(forKey: userID)
        emailDiscoverableByUserID.removeValue(forKey: userID)
    }
}
