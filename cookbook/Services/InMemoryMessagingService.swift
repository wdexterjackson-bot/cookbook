//
//  InMemoryMessagingService.swift
//  cookbook
//

import Foundation

final class InMemoryMessagingService: MessagingServicing {
    private(set) var messages: [Message] = []

    @discardableResult
    func send(type: MessageType, senderID: String, recipientID: String, payloadReference: String, expiresAt: Date?) async throws -> Message {
        let message = Message(
            id: UUID().uuidString,
            type: type,
            senderID: senderID,
            recipientID: recipientID,
            payloadReference: payloadReference,
            createdAt: .now,
            expiresAt: expiresAt,
            isRead: false,
            actionState: .pending
        )
        messages.append(message)
        return message
    }

    func fetchMessages(for userID: String) async throws -> [Message] {
        messages
            .filter { $0.recipientID == userID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func markRead(_ messageID: String, userID: String) async throws {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            throw MessagingServiceError.messageNotFound
        }
        guard messages[index].recipientID == userID else {
            throw MessagingServiceError.notAuthorized
        }
        messages[index].isRead = true
    }

    func markActioned(_ messageID: String, userID: String) async throws {
        guard let index = messages.firstIndex(where: { $0.id == messageID }) else {
            throw MessagingServiceError.messageNotFound
        }
        guard messages[index].recipientID == userID else {
            throw MessagingServiceError.notAuthorized
        }
        messages[index].actionState = .actioned
    }
}
