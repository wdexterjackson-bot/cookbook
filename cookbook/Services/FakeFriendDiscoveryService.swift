//
//  FakeFriendDiscoveryService.swift
//  cookbook
//

import Foundation

final class FakeFriendDiscoveryService: FriendDiscoveryServicing {
    var usersByEmail: [String: DiscoveredUser] = [:]
    var lookupError: Error?

    func findUser(byEmail email: String) async throws -> DiscoveredUser? {
        if let lookupError { throw lookupError }
        return usersByEmail[email]
    }
}
