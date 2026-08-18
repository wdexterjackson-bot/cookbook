//
//  InMemoryFriendsService.swift
//  cookbook
//

import Foundation

final class InMemoryFriendsService: FriendsServicing {
    private(set) var friendRequests: [String: FriendRequest] = [:]
    private(set) var friendships: [String: Friendship] = [:]

    @discardableResult
    func sendFriendRequest(from senderID: String, to recipientID: String) async throws -> FriendRequest {
        let friendshipID = Friendship.compositeID([senderID, recipientID])
        if friendships[friendshipID] != nil {
            throw FriendsServiceError.alreadyFriends
        }

        let forwardID = FriendRequest.compositeID(senderID: senderID, recipientID: recipientID)
        let reverseID = FriendRequest.compositeID(senderID: recipientID, recipientID: senderID)

        if var reverseRequest = friendRequests[reverseID], reverseRequest.status == .pending {
            reverseRequest.status = .accepted
            reverseRequest.respondedAt = .now
            friendRequests[reverseID] = reverseRequest
            friendships[friendshipID] = Friendship(id: friendshipID, userIDs: [senderID, recipientID], becameFriendsAt: .now)
            return reverseRequest
        }

        if var forwardRequest = friendRequests[forwardID] {
            if forwardRequest.status == .declined {
                forwardRequest.status = .pending
                forwardRequest.createdAt = .now
                forwardRequest.respondedAt = nil
                friendRequests[forwardID] = forwardRequest
            }
            return forwardRequest
        }

        let request = FriendRequest(
            id: forwardID, senderID: senderID, recipientID: recipientID,
            status: .pending, createdAt: .now, respondedAt: nil
        )
        friendRequests[forwardID] = request
        return request
    }

    func respondToFriendRequest(_ requestID: String, accept: Bool, respondingUserID: String) async throws {
        guard var request = friendRequests[requestID] else {
            throw FriendsServiceError.requestNotFound
        }
        guard request.recipientID == respondingUserID else {
            throw FriendsServiceError.notAuthorized
        }
        guard request.status == .pending else {
            throw FriendsServiceError.invalidState
        }

        request.status = accept ? .accepted : .declined
        request.respondedAt = .now
        friendRequests[requestID] = request

        if accept {
            let friendshipID = Friendship.compositeID([request.senderID, request.recipientID])
            friendships[friendshipID] = Friendship(id: friendshipID, userIDs: [request.senderID, request.recipientID], becameFriendsAt: .now)
        }
    }

    func fetchFriendRequests(forRecipient userID: String) async throws -> [FriendRequest] {
        friendRequests.values.filter { $0.recipientID == userID && $0.status == .pending }
    }

    func fetchFriends(forUser userID: String) async throws -> [Friendship] {
        friendships.values.filter { $0.userIDs.contains(userID) }
    }

    func removeFriend(_ friendshipID: String, actingUserID: String) async throws {
        guard let friendship = friendships[friendshipID] else {
            return // Already gone — treat as success so a retried call is safe.
        }
        guard friendship.userIDs.contains(actingUserID) else {
            throw FriendsServiceError.notAuthorized
        }
        friendships[friendshipID] = nil
    }
}
