//
//  FriendsServicing.swift
//  cookbook
//
//  Its own protocol, not bolted onto GroupsServicing — friendship has no
//  group/membership dependency at all.
//

import Foundation

enum FriendsServiceError: Error, Equatable {
    case requestNotFound
    case notAuthorized
    case invalidState
    case alreadyFriends
}

protocol FriendsServicing {
    /// Sends a friend request from `senderID` to `recipientID`. Three
    /// special cases, all handled here rather than left to the caller:
    /// - Already friends: throws `.alreadyFriends`, no write.
    /// - A reverse request (`recipientID` → `senderID`) is already
    ///   pending: accepts it instead of creating a second, contradictory
    ///   doc — returns the now-accepted reverse request.
    /// - This same forward request was previously declined: resets it to
    ///   `.pending` with a fresh `createdAt` rather than erroring.
    /// Calling this while an identical forward request is already
    /// `.pending` is a no-op — returns the existing request unchanged.
    @discardableResult
    func sendFriendRequest(from senderID: String, to recipientID: String) async throws -> FriendRequest

    /// Only the recipient may respond, and only while still `.pending` —
    /// throws `.notAuthorized`/`.invalidState` otherwise. Accepting
    /// creates the paired `Friendship` in the same transaction as marking
    /// the request accepted.
    func respondToFriendRequest(_ requestID: String, accept: Bool, respondingUserID: String) async throws

    /// Pending requests awaiting `userID`'s decision.
    func fetchFriendRequests(forRecipient userID: String) async throws -> [FriendRequest]

    func fetchFriends(forUser userID: String) async throws -> [Friendship]

    /// Either party may remove a friendship. The `FriendRequest` doc that
    /// originated it is left as-is (historical record), same
    /// tombstone-not-delete bias this codebase already applies elsewhere.
    func removeFriend(_ friendshipID: String, actingUserID: String) async throws
}
