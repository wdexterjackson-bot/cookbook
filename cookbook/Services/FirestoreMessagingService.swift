//
//  FirestoreMessagingService.swift
//  cookbook
//
//  Collection: messages/{id}.
//

import FirebaseFirestore
import Foundation

final class FirestoreMessagingService: MessagingServicing {
    private let db = Firestore.firestore()

    @discardableResult
    func send(type: MessageType, senderID: String, recipientID: String, payloadReference: String, expiresAt: Date?) async throws -> Message {
        let message = Message(
            id: db.collection("messages").document().documentID,
            type: type,
            senderID: senderID,
            recipientID: recipientID,
            payloadReference: payloadReference,
            createdAt: .now,
            expiresAt: expiresAt,
            isRead: false,
            actionState: .pending
        )
        try db.collection("messages").document(message.id).setData(from: message)
        return message
    }

    func fetchMessages(for userID: String) async throws -> [Message] {
        let snapshot = try await db.collection("messages")
            .whereField("recipientID", isEqualTo: userID)
            .order(by: "createdAt", descending: true)
            .getDocuments()
        return try snapshot.documents.map { try $0.data(as: Message.self) }
    }

    func markRead(_ messageID: String, userID: String) async throws {
        let ref = db.collection("messages").document(messageID)
        guard let message = try await ref.getDocument().data(as: Message?.self) else {
            throw MessagingServiceError.messageNotFound
        }
        guard message.recipientID == userID else {
            throw MessagingServiceError.notAuthorized
        }
        try await ref.setData(["isRead": true], merge: true)
    }

    func markActioned(_ messageID: String, userID: String) async throws {
        let ref = db.collection("messages").document(messageID)
        guard let message = try await ref.getDocument().data(as: Message?.self) else {
            throw MessagingServiceError.messageNotFound
        }
        guard message.recipientID == userID else {
            throw MessagingServiceError.notAuthorized
        }
        try await ref.setData(["actionState": MessageActionState.actioned.rawValue], merge: true)
    }
}
