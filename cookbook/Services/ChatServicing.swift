//
//  ChatServicing.swift
//  cookbook
//
//  Its own protocol, not bolted onto MessagingServicing — a conversation
//  (many messages, ordered, both parties can read all of it) is a
//  different shape from the actionable inbox (one-shot notices, only the
//  recipient can read a given one).
//

import Foundation

enum ChatServiceError: Error, Equatable {
    case messageTextEmpty
}

extension ChatServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .messageTextEmpty: return "Type a message first."
        }
    }
}

protocol ChatServicing {
    @discardableResult
    func sendMessage(from senderID: String, to recipientID: String, text: String) async throws -> ChatMessage

    /// Full history for the conversation between these two users, oldest
    /// first — there's no pagination yet, matching every other list in
    /// this app (no infinite scroll anywhere else either).
    func fetchMessages(conversationID: String) async throws -> [ChatMessage]

    /// Marks every unread message in this conversation addressed to
    /// `recipientID` as read — called once when the recipient opens the
    /// conversation, not per-message.
    func markAllRead(conversationID: String, recipientID: String) async throws

    /// Every conversation with at least one unread message addressed to
    /// `recipientID`, keyed by the other participant's userID with how
    /// many are unread — what drives the "N unread from X" summary on
    /// the dashboard, its bell badge, and the Messages screen.
    func fetchUnreadCounts(forRecipient recipientID: String) async throws -> [String: Int]
}
