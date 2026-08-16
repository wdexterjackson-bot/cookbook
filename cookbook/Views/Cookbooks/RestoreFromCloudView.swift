//
//  RestoreFromCloudView.swift
//  cookbook
//
//  Lists a signed-in user's cloud-synced personal cookbooks and pulls one
//  down onto this device (PersonalCookbookSyncCoordinator.pull) — the
//  cloud counterpart to CookbooksHubView's existing local-file "Restore
//  from Backup." Deliberately owns its whole lifecycle (list, optional
//  overwrite confirmation, pull, success state) rather than reactively
//  coordinating alert/dismiss timing with its presenting view — the
//  parent only ever hears about a restore via a single, direct tap on
//  this view's own "Done" button, the same shape as every other
//  presentation-sequencing fix made in this app (see CookbooksHubView's
//  restore(from:) comment) rather than a reactive multi-state cascade.
//

import SwiftUI
import SwiftData

struct RestoreFromCloudView: View {
    /// Called once, from this view's own "Done" button, after a
    /// successful pull — never fired reactively alongside this view's own
    /// dismissal from anywhere else.
    let onRestored: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]

    @State private var summaries: [PersonalCookbookSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var pendingOverwrite: PersonalCookbookSummary?
    @State private var isPulling = false
    @State private var restoredTitle: String?
    @State private var restoredCookbookID: UUID?

    private let syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService()

    var body: some View {
        NavigationStack {
            Group {
                if let restoredTitle {
                    ContentUnavailableView {
                        Label("Restored", systemImage: "checkmark.circle.fill")
                    } description: {
                        Text("\"\(restoredTitle)\" is now on this device.")
                    }
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if summaries.isEmpty {
                    ContentUnavailableView(
                        "No Cloud Cookbooks",
                        systemImage: "icloud.slash",
                        description: Text("You haven't synced any personal cookbooks to the cloud yet — turn on Sync to Cloud when creating or editing one.")
                    )
                } else {
                    List(summaries) { summary in
                        Button {
                            attemptRestore(summary)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(summary.title)
                                Text(summary.updatedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .disabled(isPulling)
                    }
                    .potluckHiddenScrollBackground()
                }
            }
            .background(Color.potluckCream)
            .overlay {
                if isPulling {
                    ProgressView("Restoring…")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                }
            }
            .navigationTitle("Restore from Cloud")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(restoredTitle == nil ? "Cancel" : "Done") {
                        if let restoredCookbookID {
                            onRestored(restoredCookbookID)
                        }
                        dismiss()
                    }
                }
            }
            .task {
                await load()
            }
            .confirmationDialog(
                overwriteConfirmationMessage,
                isPresented: Binding(
                    get: { pendingOverwrite != nil },
                    set: { if !$0 { pendingOverwrite = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Replace", role: .destructive) {
                    let summary = pendingOverwrite
                    pendingOverwrite = nil
                    if let summary {
                        Task { await pull(summary) }
                    }
                }
                Button("Cancel", role: .cancel) { pendingOverwrite = nil }
            }
            .alert(
                "Couldn't Restore",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var overwriteConfirmationMessage: String {
        guard let pendingOverwrite else { return "" }
        return "This replaces your local copy of \"\(pendingOverwrite.title)\" with the cloud version — continue?"
    }

    private func attemptRestore(_ summary: PersonalCookbookSummary) {
        let existingLocally = allCookbooks.contains { $0.id == summary.id }
        if existingLocally {
            pendingOverwrite = summary
        } else {
            Task { await pull(summary) }
        }
    }

    private func load() async {
        guard let userID = accountState.currentUserID else {
            isLoading = false
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            summaries = try await syncService.fetchSyncedCookbooks(forUser: userID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pull(_ summary: PersonalCookbookSummary) async {
        guard let ownerUserID = accountState.currentUserID else { return }
        isPulling = true
        defer { isPulling = false }
        do {
            let cookbook = try await PersonalCookbookSyncCoordinator.pull(
                cookbookID: summary.id, ownerUserID: ownerUserID,
                modelContext: modelContext, syncService: syncService
            )
            restoredTitle = cookbook.title
            restoredCookbookID = cookbook.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    RestoreFromCloudView(onRestored: { _ in })
        .modelContainer(for: Cookbook.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
