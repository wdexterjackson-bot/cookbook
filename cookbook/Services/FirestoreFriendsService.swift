//
//  FirestoreFriendsService.swift
//  cookbook
//
//  Collections: friendRequests/{senderID}_{recipientID},
//  friendships/{sortedID}. See firestore.rules' friendRequests/friendships
//  match blocks for the getAfter()-paired create enforcement this mirrors
//  client-side.
//

import FirebaseFirestore
import Foundation

final class FirestoreFriendsService: FriendsServicing {
    private let db = Firestore.firestore()

    @discardableResult
    func sendFriendRequest(from senderID: String, to recipientID: String) async throws -> FriendRequest {
        let friendshipRef = db.collection("friendships").document(Friendship.compositeID([senderID, recipientID]))
        if try await friendshipRef.getDocument().exists {
            throw FriendsServiceError.alreadyFriends
        }

        let forwardRef = db.collection("friendRequests").document(FriendRequest.compositeID(senderID: senderID, recipientID: recipientID))
        let reverseRef = db.collection("friendRequests").document(FriendRequest.compositeID(senderID: recipientID, recipientID: senderID))

        if let reverseSnapshot = try? await reverseRef.getDocument(),
           var reverseRequest = try reverseSnapshot.data(as: FriendRequest?.self),
           reverseRequest.status == .pending {
            // Mutual/simultaneous request — accept the existing reverse
            // request instead of creating a second, contradictory doc.
            reverseRequest.status = .accepted
            reverseRequest.respondedAt = .now
            let friendship = Friendship(id: friendshipRef.documentID, userIDs: [senderID, recipientID], becameFriendsAt: .now)
            let batch = db.batch()
            try batch.setData(from: reverseRequest, forDocument: reverseRef)
            try batch.setData(from: friendship, forDocument: friendshipRef)
            try await batch.commit()
            return reverseRequest
        }

        if let forwardSnapshot = try? await forwardRef.getDocument(),
           var forwardRequest = try forwardSnapshot.data(as: FriendRequest?.self) {
            if forwardRequest.status == .declined {
                forwardRequest.status = .pending
                forwardRequest.createdAt = .now
                forwardRequest.respondedAt = nil
                try forwardRef.setData(from: forwardRequest)
            }
            return forwardRequest
        }

        let request = FriendRequest(
            id: forwardRef.documentID,
            senderID: senderID,
            recipientID: recipientID,
            status: .pending,
            createdAt: .now,
            respondedAt: nil
        )
        try forwardRef.setData(from: request)
        return request
    }

    func respondToFriendRequest(_ requestID: String, accept: Bool, respondingUserID: String) async throws {
        let ref = db.collection("friendRequests").document(requestID)
        guard var request = try await ref.getDocument().data(as: FriendRequest?.self) else {
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

        if accept {
            let friendshipRef = db.collection("friendships").document(Friendship.compositeID([request.senderID, request.recipientID]))
            let friendship = Friendship(id: friendshipRef.documentID, userIDs: [request.senderID, request.recipientID], becameFriendsAt: .now)
            let batch = db.batch()
            try batch.setData(from: request, forDocument: ref)
            try batch.setData(from: friendship, forDocument: friendshipRef)
            try await batch.commit()
        } else {
            try ref.setData(from: request)
        }
    }

    func fetchFriendRequests(forRecipient userID: String) async throws -> [FriendRequest] {
        let snapshot = try await db.collection("friendRequests")
            .whereField("recipientID", isEqualTo: userID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: FriendRequest.self) }
    }

    func fetchFriends(forUser userID: String) async throws -> [Friendship] {
        let snapshot = try await db.collection("friendships")
            .whereField("userIDs", arrayContains: userID)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: Friendship.self) }
    }

    func removeFriend(_ friendshipID: String, actingUserID: String) async throws {
        let ref = db.collection("friendships").document(friendshipID)
        guard let friendship = try await ref.getDocument().data(as: Friendship?.self) else {
            return // Already gone — treat as success so a retried call is safe.
        }
        guard friendship.userIDs.contains(actingUserID) else {
            throw FriendsServiceError.notAuthorized
        }
        try await ref.delete()
    }
}
