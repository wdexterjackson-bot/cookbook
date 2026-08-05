//
//  MessagingServicing.swift
//  cookbook
//
//  Data layer for the actionable inbox (MSG-001). UI lands in Milestone 2G;
//  this just gets messages in and out of Firestore.
//

import Foundation

enum MessagingServiceError: Error, Equatable {
    case messageNotFound
    case notAuthorized
}

protocol MessagingServicing {
    @discardableResult
    func send(type: MessageType, senderID: String, recipientID: String, payloadReference: String, expiresAt: Date?) async throws -> Message
    func fetchMessages(for userID: String) async throws -> [Message]
    func markRead(_ messageID: String, userID: String) async throws
    func markActioned(_ messageID: String, userID: String) async throws
}
