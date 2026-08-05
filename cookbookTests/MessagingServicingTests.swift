//
//  MessagingServicingTests.swift
//  cookbookTests
//

import Foundation
import Testing
@testable import cookbook

struct MessagingServicingTests {

    @Test func fetchMessagesReturnsOnlyThatRecipientsSortedNewestFirst() async throws {
        let service = InMemoryMessagingService()
        try await service.send(type: .systemNotice, senderID: "system", recipientID: "alice", payloadReference: "older", expiresAt: nil)
        try await service.send(type: .systemNotice, senderID: "system", recipientID: "bob", payloadReference: "not-alices", expiresAt: nil)
        try await service.send(type: .systemNotice, senderID: "system", recipientID: "alice", payloadReference: "newer", expiresAt: nil)

        let messages = try await service.fetchMessages(for: "alice")

        #expect(messages.count == 2)
        #expect(messages.allSatisfy { $0.recipientID == "alice" })
    }

    @Test func markReadRequiresBeingTheRecipient() async throws {
        let service = InMemoryMessagingService()
        let message = try await service.send(type: .groupInvitation, senderID: "alice", recipientID: "bob", payloadReference: "invite-1", expiresAt: nil)

        await #expect(throws: MessagingServiceError.notAuthorized) {
            try await service.markRead(message.id, userID: "carol")
        }

        try await service.markRead(message.id, userID: "bob")
        let messages = try await service.fetchMessages(for: "bob")
        #expect(messages.first?.isRead == true)
    }

    @Test func markActionedUpdatesActionState() async throws {
        let service = InMemoryMessagingService()
        let message = try await service.send(type: .joinRequestForAdmin, senderID: "bob", recipientID: "alice", payloadReference: "req-1", expiresAt: nil)

        try await service.markActioned(message.id, userID: "alice")

        let messages = try await service.fetchMessages(for: "alice")
        #expect(messages.first?.actionState == .actioned)
    }
}
