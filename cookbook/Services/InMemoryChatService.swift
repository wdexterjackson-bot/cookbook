//
//  InMemoryChatService.swift
//  cookbook
//

import Foundation

final class InMemoryChatService: ChatServicing {
    private(set) var messages: [ChatMessage] = []

    @discardableResult
    func sendMessage(from senderID: String, to recipientID: String, text: String) async throws -> ChatMessage {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChatServiceError.messageTextEmpty }
        let message = ChatMessage(
            id: UUID().uuidString,
            conversationID: ChatMessage.conversationID([senderID, recipientID]),
            senderID: senderID,
            recipientID: recipientID,
            text: trimmed,
            sentAt: .now,
            isRead: false
        )
        messages.append(message)
        return message
    }

    func fetchMessages(conversationID: String) async throws -> [ChatMessage] {
        messages
            .filter { $0.conversationID == conversationID }
            .sorted { $0.sentAt < $1.sentAt }
    }

    func markAllRead(conversationID: String, recipientID: String) async throws {
        for index in messages.indices where messages[index].conversationID == conversationID
            && messages[index].recipientID == recipientID && !messages[index].isRead {
            messages[index].isRead = true
        }
    }

    func fetchUnreadCounts(forRecipient recipientID: String) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        for message in messages where message.recipientID == recipientID && !message.isRead {
            counts[message.senderID, default: 0] += 1
        }
        return counts
    }
}
