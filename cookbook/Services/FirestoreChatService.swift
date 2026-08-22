//
//  FirestoreChatService.swift
//  cookbook
//
//  Collection: directMessages/{id} — flat, not a subcollection, matching
//  friendRequests/friendships/messages' own flat-collection convention.
//  No real-time listener: like every other list in this app, the chat view
//  polls (fetch on appear + a lightweight foreground timer) rather than
//  subscribing — there is no addSnapshotListener anywhere in this codebase
//  yet, and introducing one here would be a first, not a fit-in.
//

import FirebaseFirestore
import Foundation

final class FirestoreChatService: ChatServicing {
    private let db = Firestore.firestore()

    @discardableResult
    func sendMessage(from senderID: String, to recipientID: String, text: String) async throws -> ChatMessage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatServiceError.messageTextEmpty }
        let message = ChatMessage(
            id: db.collection("directMessages").document().documentID,
            conversationID: ChatMessage.conversationID([senderID, recipientID]),
            senderID: senderID,
            recipientID: recipientID,
            text: trimmed,
            sentAt: .now,
            isRead: false
        )
        // setData(from:) (the Codable convenience, no completion handler)
        // is fire-and-forget — it returns as soon as encoding succeeds,
        // without ever waiting on or surfacing the actual write's result,
        // so a rules rejection was silently swallowed: this call "threw
        // nothing," the sender's UI showed the message as sent, and it
        // never actually reached Firestore for the recipient to read. Same
        // gotcha FirestoreUserProfileService.setLocation already documents
        // — encoding to a dictionary first and using the plain
        // setData(_:merge:) gets the real async throws overload instead.
        let encoded = try Firestore.Encoder().encode(message)
        try await db.collection("directMessages").document(message.id).setData(encoded)
        return message
    }

    func fetchMessages(conversationID: String) async throws -> [ChatMessage] {
        let snapshot = try await db.collection("directMessages")
            .whereField("conversationID", isEqualTo: conversationID)
            .order(by: "sentAt")
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: ChatMessage.self) }
    }

    func markAllRead(conversationID: String, recipientID: String) async throws {
        // Client-side filter rather than a third whereField clause — this
        // conversation's full history is already small and already fetched
        // by the view that calls this, and avoiding a 3-field composite
        // index keeps this from needing a firestore.indexes.json entry of
        // its own.
        let messages = try await fetchMessages(conversationID: conversationID)
        for message in messages where message.recipientID == recipientID && !message.isRead {
            try await db.collection("directMessages").document(message.id).setData(["isRead": true], merge: true)
        }
    }

    func fetchUnreadCounts(forRecipient recipientID: String) async throws -> [String: Int] {
        let snapshot = try await db.collection("directMessages")
            .whereField("recipientID", isEqualTo: recipientID)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        var counts: [String: Int] = [:]
        for document in snapshot.documents {
            guard let senderID = document.data()["senderID"] as? String else { continue }
            counts[senderID, default: 0] += 1
        }
        return counts
    }
}
