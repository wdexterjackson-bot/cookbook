//
//  FirebaseFriendDiscoveryService.swift
//  cookbook
//

import FirebaseFunctions
import Foundation

final class FirebaseFriendDiscoveryService: FriendDiscoveryServicing {
    private let functions = Functions.functions()

    func findUser(byEmail email: String) async throws -> DiscoveredUser? {
        let callable = functions.httpsCallable("findUserByEmail")
        let result = try await callable.call(["email": email])

        guard let data = result.data as? [String: Any], data["found"] as? Bool == true,
              let userID = data["userID"] as? String else {
            return nil
        }
        return DiscoveredUser(userID: userID, displayName: data["displayName"] as? String)
    }
}
