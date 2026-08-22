//
//  ChatMessage.swift
//  cookbook
//
//  Direct friend-to-friend chat — separate from Message/MessagingServicing
//  (that's an actionable inbox notification, not a conversation: no
//  conversationID, and nothing generates one per chat message). One
//  conversation per friendship, id'd the same sorted-pair way Friendship
//  itself is, so there's exactly one thread between any two friends.
//

import Foundation

struct ChatMessage: Codable, Identifiable, Equatable {
    var id: String
    var conversationID: String
    var senderID: String
    var recipientID: String
    var text: String
    var sentAt: Date
    var isRead: Bool
}

extension ChatMessage {
    /// Same sorted-pair scheme as Friendship.compositeID — a chat only ever
    /// exists between two friends, so reusing it keeps "the conversation
    /// with this friend" and "the friendship with this friend" addressable
    /// the same way.
    static func conversationID(_ userIDs: [String]) -> String {
        Friendship.compositeID(userIDs)
    }
}
