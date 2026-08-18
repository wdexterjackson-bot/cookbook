//
//  PublicationCommentsView.swift
//  cookbook
//
//  Only ever reached when Publication.commentsEnabled is true (see
//  GroupCookbookView's own gate on the entry point) — this view itself
//  still checks it too, defensively, in case a stale cached publication
//  value is passed in.
//

import SwiftUI

struct PublicationCommentsView: View {
    let publication: Publication
    /// The current user's own membership in the publication's group —
    /// used only to decide whether to *show* a delete affordance on
    /// someone else's comment (admin) alongside their own (author).
    /// PublicationsServicing.deleteComment re-verifies this itself
    /// server-side regardless.
    let membership: Membership
    let publicationsService: PublicationsServicing

    @Environment(AccountState.self) private var accountState
    @State private var comments: [RecipeComment] = []
    @State private var newCommentText = ""
    @State private var isLoading = false
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !publication.commentsEnabled {
                Text("Comments are turned off for this recipe.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    if comments.isEmpty && !isLoading {
                        Text("No comments yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(comments) { comment in
                            commentRow(comment)
                        }
                    }
                }

                Section {
                    TextField("Add a comment…", text: $newCommentText, axis: .vertical)
                    Button("Post") {
                        Task { await postComment() }
                    }
                    .disabled(isPosting || newCommentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
        .navigationTitle("Comments")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadComments()
        }
        .refreshable {
            await loadComments()
        }
    }

    @ViewBuilder
    private func commentRow(_ comment: RecipeComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(comment.authorDisplayName)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(comment.text)
        }
        .padding(.vertical, 2)
        #if !os(tvOS)
        .swipeActions {
            if canDelete(comment) {
                Button("Delete", role: .destructive) {
                    Task { await delete(comment) }
                }
            }
        }
        #endif
    }

    private func canDelete(_ comment: RecipeComment) -> Bool {
        comment.authorUserID == accountState.currentUserID || membership.role == .admin
    }

    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }
        comments = (try? await publicationsService.fetchComments(publication.id)) ?? []
    }

    private func postComment() async {
        guard let userID = accountState.currentUserID else { return }
        let text = newCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPosting = true
        errorMessage = nil
        defer { isPosting = false }
        do {
            _ = try await publicationsService.addComment(
                publication.id,
                authorUserID: userID,
                authorDisplayName: accountState.currentUserDisplayName ?? "Someone",
                text: text
            )
            newCommentText = ""
            await loadComments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ comment: RecipeComment) async {
        guard let userID = accountState.currentUserID else { return }
        errorMessage = nil
        do {
            try await publicationsService.deleteComment(comment.id, publicationID: publication.id, actingUserID: userID)
            await loadComments()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
