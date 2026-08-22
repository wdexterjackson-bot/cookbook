//
//  ChatServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct ChatServicingTests {

    @Test func sendingAMessageMakesItFetchableByBothParties() async throws {
        let service = InMemoryChatService()

        let sent = try await service.sendMessage(from: "alice", to: "bob", text: "Hey!")

        let conversationID = ChatMessage.conversationID(["alice", "bob"])
        #expect(sent.conversationID == conversationID)
        let messages = try await service.fetchMessages(conversationID: conversationID)
        #expect(messages.map(\.id) == [sent.id])
        #expect(sent.isRead == false)
    }

    @Test func conversationIDIsTheSameRegardlessOfSenderRecipientOrder() async throws {
        let service = InMemoryChatService()
        _ = try await service.sendMessage(from: "alice", to: "bob", text: "Hi")
        _ = try await service.sendMessage(from: "bob", to: "alice", text: "Hi back")

        let messages = try await service.fetchMessages(conversationID: ChatMessage.conversationID(["bob", "alice"]))

        #expect(messages.count == 2)
    }

    @Test func messagesComeBackOldestFirst() async throws {
        let service = InMemoryChatService()
        let first = try await service.sendMessage(from: "alice", to: "bob", text: "one")
        let second = try await service.sendMessage(from: "alice", to: "bob", text: "two")

        let messages = try await service.fetchMessages(conversationID: ChatMessage.conversationID(["alice", "bob"]))

        #expect(messages.map(\.id) == [first.id, second.id])
    }

    @Test func sendingBlankTextThrows() async throws {
        let service = InMemoryChatService()

        await #expect(throws: ChatServiceError.messageTextEmpty) {
            try await service.sendMessage(from: "alice", to: "bob", text: "   ")
        }
    }

    @Test func markAllReadOnlyAffectsMessagesAddressedToThatRecipient() async throws {
        let service = InMemoryChatService()
        _ = try await service.sendMessage(from: "alice", to: "bob", text: "one")
        _ = try await service.sendMessage(from: "bob", to: "alice", text: "two")
        let conversationID = ChatMessage.conversationID(["alice", "bob"])

        try await service.markAllRead(conversationID: conversationID, recipientID: "bob")

        let messages = try await service.fetchMessages(conversationID: conversationID)
        #expect(messages.first { $0.recipientID == "bob" }?.isRead == true)
        #expect(messages.first { $0.recipientID == "alice" }?.isRead == false)
    }

    @Test func fetchUnreadCountsGroupsByTheOtherParty() async throws {
        let service = InMemoryChatService()
        _ = try await service.sendMessage(from: "alice", to: "bob", text: "one")
        _ = try await service.sendMessage(from: "alice", to: "bob", text: "two")
        _ = try await service.sendMessage(from: "carol", to: "bob", text: "hi")
        _ = try await service.sendMessage(from: "bob", to: "alice", text: "reply") // not bob's unread

        let counts = try await service.fetchUnreadCounts(forRecipient: "bob")

        #expect(counts == ["alice": 2, "carol": 1])
    }

    @Test func fetchUnreadCountsExcludesAlreadyReadMessages() async throws {
        let service = InMemoryChatService()
        _ = try await service.sendMessage(from: "alice", to: "bob", text: "one")
        try await service.markAllRead(conversationID: ChatMessage.conversationID(["alice", "bob"]), recipientID: "bob")

        let counts = try await service.fetchUnreadCounts(forRecipient: "bob")

        #expect(counts.isEmpty)
    }
}
