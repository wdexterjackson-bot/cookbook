//
//  ChatView.swift
//  cookbook
//
//  Direct friend-to-friend chat. Pushed from FriendsListView by tapping a
//  friend row. No live listener (see FirestoreChatService's own doc
//  comment) — a light foreground poll while this view is open gives a
//  near-real-time feel without introducing this app's first
//  addSnapshotListener.
//

import SwiftUI

// Text-entry chat isn't a tvOS-appropriate surface (no keyboard, no
// roundedBorder text field style) — FriendsListView already excludes the
// navigation entry point on tvOS (see its own #if os(tvOS) branch), so
// this whole view is compiled out to match rather than left dead code.
#if !os(tvOS)
struct ChatView: View {
    let friendUserID: String
    let chatService: ChatServicing

    @Environment(AccountState.self) private var accountState
    @State private var messages: [ChatMessage] = []
    @State private var draftText = ""
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var pollTask: Task<Void, Never>?
    @State private var friendlyNames = FriendlyNameDirectory()

    private var conversationID: String? {
        guard let userID = accountState.currentUserID else { return nil }
        return ChatMessage.conversationID([userID, friendUserID])
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if messages.isEmpty {
                            Text("No messages yet — say hello.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        }
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let lastID = messages.last?.id {
                        withAnimation {
                            scrollProxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }

            HStack(spacing: 8) {
                TextField("Message", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Send")
            }
            .padding()
        }
        .background(Color.potluckCream)
        .navigationTitle(friendlyNames.label(for: friendUserID))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await friendlyNames.load(userIDs: [friendUserID])
            await load()
            startPolling()
        }
        .onDisappear {
            pollTask?.cancel()
        }
    }

    @ViewBuilder
    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderID == accountState.currentUserID
        HStack {
            if isMine { Spacer(minLength: 40) }
            Text(message.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isMine ? Self.outgoingBubbleColor : Self.incomingBubbleColor)
                // iMessage always keeps sent-bubble text white regardless
                // of light/dark mode; the incoming bubble's gray does
                // adapt (lighter in light mode, darker in dark mode), so
                // its text stays .primary to track that automatically.
                .foregroundStyle(isMine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            if !isMine { Spacer(minLength: 40) }
        }
    }

    /// iMessage's own sent-bubble blue (iOS systemBlue) — deliberately not
    /// this app's potluckSage brand color, per the "iMessage color scheme"
    /// request.
    private static let outgoingBubbleColor = Color(red: 0 / 255, green: 122 / 255, blue: 255 / 255)

    /// iMessage's received-bubble gray. UIKit/AppKit's system grays adapt
    /// to light/dark automatically (unlike a fixed Color literal), so
    /// this stays platform-specific rather than one shared constant.
    private static var incomingBubbleColor: Color {
        #if os(iOS)
        Color(uiColor: .systemGray5)
        #elseif os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color.gray.opacity(0.2)
        #endif
    }

    /// Polls every few seconds while this conversation is open — cancelled
    /// on disappear via pollTask, never runs in the background.
    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await load()
            }
        }
    }

    private func load() async {
        guard let userID = accountState.currentUserID, let conversationID else { return }
        do {
            messages = try await chatService.fetchMessages(conversationID: conversationID)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load messages: \(error.localizedDescription)"
            return
        }
        // Best-effort, deliberately not surfaced — marking a message read
        // is bookkeeping, not something that should ever show the whole
        // conversation a scary permissions error on a recurring 4-second
        // poll if it hiccups. A failure here just leaves the sender's
        // unread state slightly stale.
        try? await chatService.markAllRead(conversationID: conversationID, recipientID: userID)
    }

    private func send() async {
        guard let userID = accountState.currentUserID else { return }
        let text = draftText
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            let sent = try await chatService.sendMessage(from: userID, to: friendUserID, text: text)
            messages.append(sent)
            draftText = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(friendUserID: "friend-1", chatService: InMemoryChatService())
    }
    .environment(AccountState(authService: FakeAuthService()))
}
#endif
