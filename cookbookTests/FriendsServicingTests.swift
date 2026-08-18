//
//  FriendsServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct FriendsServicingTests {

    @Test func sendingARequestCreatesAPendingRequest() async throws {
        let service = InMemoryFriendsService()

        let request = try await service.sendFriendRequest(from: "alice", to: "bob")

        #expect(request.status == .pending)
        #expect(request.senderID == "alice")
        #expect(request.recipientID == "bob")
        let pendingForBob = try await service.fetchFriendRequests(forRecipient: "bob")
        #expect(pendingForBob.map(\.id) == [request.id])
    }

    @Test func sendingTheSameRequestTwiceWhileStillPendingIsANoOp() async throws {
        let service = InMemoryFriendsService()
        let first = try await service.sendFriendRequest(from: "alice", to: "bob")

        let second = try await service.sendFriendRequest(from: "alice", to: "bob")

        #expect(first.id == second.id)
        #expect(second.status == .pending)
    }

    @Test func acceptingCreatesAFriendship() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")

        try await service.respondToFriendRequest(request.id, accept: true, respondingUserID: "bob")

        let aliceFriends = try await service.fetchFriends(forUser: "alice")
        let bobFriends = try await service.fetchFriends(forUser: "bob")
        #expect(aliceFriends.count == 1)
        #expect(bobFriends.count == 1)
        #expect(aliceFriends.first?.userIDs.sorted() == ["alice", "bob"])
        // No longer pending once decided.
        #expect(try await service.fetchFriendRequests(forRecipient: "bob").isEmpty)
    }

    @Test func decliningDoesNotCreateAFriendship() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")

        try await service.respondToFriendRequest(request.id, accept: false, respondingUserID: "bob")

        #expect(try await service.fetchFriends(forUser: "alice").isEmpty)
    }

    @Test func onlyTheRecipientCanRespond() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")

        await #expect(throws: FriendsServiceError.notAuthorized) {
            try await service.respondToFriendRequest(request.id, accept: true, respondingUserID: "carol")
        }
    }

    @Test func cannotRespondToAnAlreadyDecidedRequest() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")
        try await service.respondToFriendRequest(request.id, accept: true, respondingUserID: "bob")

        await #expect(throws: FriendsServiceError.invalidState) {
            try await service.respondToFriendRequest(request.id, accept: false, respondingUserID: "bob")
        }
    }

    // Real correctness gap #1 from the plan review: A sends B a request,
    // then B sends A one before either responds — must resolve to exactly
    // one Friendship, not two contradictory pending requests or a race
    // creating the same Friendship doc twice.
    @Test func simultaneousMutualRequestsResolveToOneFriendship() async throws {
        let service = InMemoryFriendsService()
        _ = try await service.sendFriendRequest(from: "alice", to: "bob")

        let bobsRequest = try await service.sendFriendRequest(from: "bob", to: "alice")

        // Bob's "send" was actually an accept of Alice's existing request.
        #expect(bobsRequest.senderID == "alice")
        #expect(bobsRequest.recipientID == "bob")
        #expect(bobsRequest.status == .accepted)
        let aliceFriends = try await service.fetchFriends(forUser: "alice")
        #expect(aliceFriends.count == 1)
        // Neither side has a lingering pending request.
        #expect(try await service.fetchFriendRequests(forRecipient: "alice").isEmpty)
        #expect(try await service.fetchFriendRequests(forRecipient: "bob").isEmpty)
    }

    // Real correctness gap #2 from the plan review: re-sending after an
    // earlier decline must reset the existing doc back to pending, not
    // error on "already exists."
    @Test func reRequestingAfterADeclineResetsToPending() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")
        try await service.respondToFriendRequest(request.id, accept: false, respondingUserID: "bob")

        let resent = try await service.sendFriendRequest(from: "alice", to: "bob")

        #expect(resent.id == request.id)
        #expect(resent.status == .pending)
        let pendingForBob = try await service.fetchFriendRequests(forRecipient: "bob")
        #expect(pendingForBob.map(\.id) == [resent.id])
    }

    // The other direction after a decline — a fresh request, not a reset
    // of the declined doc, since it's a genuinely different doc ID.
    @Test func theOriginalRecipientCanSendTheirOwnRequestAfterDeclining() async throws {
        let service = InMemoryFriendsService()
        let original = try await service.sendFriendRequest(from: "alice", to: "bob")
        try await service.respondToFriendRequest(original.id, accept: false, respondingUserID: "bob")

        let bobsRequest = try await service.sendFriendRequest(from: "bob", to: "alice")

        #expect(bobsRequest.id != original.id)
        #expect(bobsRequest.status == .pending)
    }

    @Test func cannotSendARequestToAnExistingFriend() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")
        try await service.respondToFriendRequest(request.id, accept: true, respondingUserID: "bob")

        await #expect(throws: FriendsServiceError.alreadyFriends) {
            try await service.sendFriendRequest(from: "alice", to: "bob")
        }
    }

    @Test func eitherPartyCanRemoveAFriendship() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")
        try await service.respondToFriendRequest(request.id, accept: true, respondingUserID: "bob")
        let friendshipID = try #require(await service.fetchFriends(forUser: "alice").first?.id)

        try await service.removeFriend(friendshipID, actingUserID: "bob")

        #expect(try await service.fetchFriends(forUser: "alice").isEmpty)
    }

    @Test func aThirdPartyCannotRemoveSomeoneElsesFriendship() async throws {
        let service = InMemoryFriendsService()
        let request = try await service.sendFriendRequest(from: "alice", to: "bob")
        try await service.respondToFriendRequest(request.id, accept: true, respondingUserID: "bob")
        let friendshipID = try #require(await service.fetchFriends(forUser: "alice").first?.id)

        await #expect(throws: FriendsServiceError.notAuthorized) {
            try await service.removeFriend(friendshipID, actingUserID: "carol")
        }
    }
}
