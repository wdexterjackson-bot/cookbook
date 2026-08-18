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
           let peek = try reverseSnapshot.data(as: FriendRequest?.self),
           peek.status == .pending {
            // Mutual/simultaneous request — accept the existing reverse
            // request instead of creating a second, contradictory doc.
            // Not rate-limited: this accepts something already sent to
            // `senderID`, it doesn't send a new one.
            //
            // Wrapped in a transaction with a fresh in-transaction read —
            // the plain read-then-write this used to be could race
            // against the *other* party independently acting on the same
            // reverse request at nearly the same moment (respondToFriendRequest/
            // cancelFriendRequest, called from another of their own
            // signed-in devices, or as part of AccountDeletionCoordinator's
            // best-effort cleanup) — leaving the request's final status
            // inconsistent with whether a friendships doc actually exists.
            let result: Any = try await db.runTransaction { [db] transaction, errorPointer -> Any? in
                do {
                    guard var reverseRequest = try transaction.getDocument(reverseRef).data(as: FriendRequest?.self),
                          reverseRequest.status == .pending else {
                        errorPointer?.pointee = FriendsServiceError.invalidState as NSError
                        return nil
                    }
                    reverseRequest.status = .accepted
                    reverseRequest.respondedAt = .now
                    let friendship = Friendship(id: friendshipRef.documentID, userIDs: [senderID, recipientID], becameFriendsAt: .now)
                    try transaction.setData(from: reverseRequest, forDocument: reverseRef)
                    try transaction.setData(from: friendship, forDocument: friendshipRef)
                    return reverseRequest
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            }
            guard let reverseRequest = result as? FriendRequest else {
                throw FriendsServiceError.invalidState
            }
            return reverseRequest
        }

        if let forwardSnapshot = try? await forwardRef.getDocument(),
           var forwardRequest = try forwardSnapshot.data(as: FriendRequest?.self) {
            if forwardRequest.status == .declined || forwardRequest.status == .cancelled {
                forwardRequest.status = .pending
                forwardRequest.createdAt = .now
                forwardRequest.respondedAt = nil
                let batch = db.batch()
                try batch.setData(from: forwardRequest, forDocument: forwardRef)
                try await payFriendRequestRateLimit(for: senderID, in: batch)
                try await batch.commit()
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
        let batch = db.batch()
        try batch.setData(from: request, forDocument: forwardRef)
        try await payFriendRequestRateLimit(for: senderID, in: batch)
        try await batch.commit()
        return request
    }

    /// SAFE-002: pairs the actual friendRequests create/reset write with an
    /// increment to this sender's rolling-window counter, in the same
    /// batch — firestore.rules' friendRequestRateLimitPaid() rejects the
    /// whole batch unless this write is present and reflects a real,
    /// rule-validated increment. See that function's doc comment.
    private func payFriendRequestRateLimit(for senderID: String, in batch: WriteBatch) async throws {
        let ref = db.collection("friendRequestRateLimits").document(senderID)
        let snapshot = try? await ref.getDocument()
        let windowSeconds: TimeInterval = 3600

        // windowStart must be FieldValue.serverTimestamp() (not a
        // client-computed Date) whenever it's (re)set — firestore.rules'
        // create/reset branches require it to equal request.time exactly,
        // which only a server-resolved sentinel can guarantee given
        // client/server clock skew.
        if let data = snapshot?.data(),
           let windowStart = data["windowStart"] as? Timestamp,
           let count = data["count"] as? Int,
           Date().timeIntervalSince(windowStart.dateValue()) <= windowSeconds {
            batch.setData(["windowStart": windowStart, "count": count + 1], forDocument: ref)
        } else {
            batch.setData(["windowStart": FieldValue.serverTimestamp(), "count": 1], forDocument: ref)
        }
    }

    /// Transactional, with a fresh in-transaction read of `request` — a
    /// plain read-then-write here let two independent actors racing on
    /// the same request (the other party responding at the exact moment
    /// AccountDeletionCoordinator's best-effort cleanup cancels it, or the
    /// same account acting from two signed-in devices at once — a phone
    /// and a TV-paired session, both showing the same stale pending
    /// request) leave the request's final status inconsistent with
    /// whether a friendships doc actually got created.
    func respondToFriendRequest(_ requestID: String, accept: Bool, respondingUserID: String) async throws {
        let ref = db.collection("friendRequests").document(requestID)
        _ = try await db.runTransaction { [db] transaction, errorPointer -> Any? in
            do {
                guard var request = try transaction.getDocument(ref).data(as: FriendRequest?.self) else {
                    errorPointer?.pointee = FriendsServiceError.requestNotFound as NSError
                    return nil
                }
                guard request.recipientID == respondingUserID else {
                    errorPointer?.pointee = FriendsServiceError.notAuthorized as NSError
                    return nil
                }
                guard request.status == .pending else {
                    errorPointer?.pointee = FriendsServiceError.invalidState as NSError
                    return nil
                }
                request.status = accept ? .accepted : .declined
                request.respondedAt = .now
                try transaction.setData(from: request, forDocument: ref)
                if accept {
                    let friendshipRef = db.collection("friendships").document(Friendship.compositeID([request.senderID, request.recipientID]))
                    let friendship = Friendship(id: friendshipRef.documentID, userIDs: [request.senderID, request.recipientID], becameFriendsAt: .now)
                    try transaction.setData(from: friendship, forDocument: friendshipRef)
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            return nil
        }
    }

    /// Transactional for the same reason as respondToFriendRequest above.
    func cancelFriendRequest(_ requestID: String, actingUserID: String) async throws {
        let ref = db.collection("friendRequests").document(requestID)
        _ = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                guard var request = try transaction.getDocument(ref).data(as: FriendRequest?.self) else {
                    errorPointer?.pointee = FriendsServiceError.requestNotFound as NSError
                    return nil
                }
                guard request.senderID == actingUserID else {
                    errorPointer?.pointee = FriendsServiceError.notAuthorized as NSError
                    return nil
                }
                guard request.status == .pending else {
                    errorPointer?.pointee = FriendsServiceError.invalidState as NSError
                    return nil
                }
                request.status = .cancelled
                request.respondedAt = .now
                try transaction.setData(from: request, forDocument: ref)
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
            return nil
        }
    }

    func fetchFriendRequests(forRecipient userID: String) async throws -> [FriendRequest] {
        let snapshot = try await db.collection("friendRequests")
            .whereField("recipientID", isEqualTo: userID)
            .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: FriendRequest.self) }
    }

    func fetchFriendRequests(bySender userID: String) async throws -> [FriendRequest] {
        let snapshot = try await db.collection("friendRequests")
            .whereField("senderID", isEqualTo: userID)
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
