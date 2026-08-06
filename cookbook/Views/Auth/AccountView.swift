//
//  AccountView.swift
//  cookbook
//
//  Minimal account entry point for Milestone 2A — a full Profile tab
//  (purchases, memberships, data export) is later, group-lifecycle-adjacent
//  scope. This just surfaces sign-in state and a way in/out of it.
//

import SwiftUI
import SwiftData

struct AccountView: View {
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingSignIn = false
    @State private var isPresentingMembership = false
    @State private var isPresentingDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var signOutErrorMessage: String?
    @State private var deleteAccountErrorMessage: String?
    @State private var fullNameDraft = ""
    @State private var isSavingName = false
    @State private var saveNameErrorMessage: String?

    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()
    private let groupsService: GroupsServicing = FirestoreGroupsService()

    var body: some View {
        NavigationStack {
            Form {
                if accountState.isSignedIn {
                    Section("Account") {
                        LabeledContent("Signed in", value: accountState.currentUserID ?? "")
                        TextField("Full Name", text: $fullNameDraft)
                            #if os(iOS)
                            .textInputAutocapitalization(.words)
                            #endif
                            .onSubmit { Task { await saveFullName() } }
                        if fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines) != (accountState.currentUserDisplayName ?? "") {
                            Button("Save Name") {
                                Task { await saveFullName() }
                            }
                            .disabled(isSavingName || fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let saveNameErrorMessage {
                            Text(saveNameErrorMessage).foregroundStyle(.red)
                        }
                        Button("Sign Out", role: .destructive) {
                            signOut()
                        }
                    }

                    Section("Membership") {
                        Button("View Membership & Credits") {
                            isPresentingMembership = true
                        }
                    }

                    Section {
                        Button("Delete Account", role: .destructive) {
                            isPresentingDeleteConfirmation = true
                        }
                        .disabled(isDeletingAccount)
                    } footer: {
                        Text("Permanently deletes your account and everything tied to it — recipes, cookbooks, and Family Cookbook memberships. This cannot be undone.")
                    }

                    if isDeletingAccount {
                        ProgressView()
                    }
                    if let deleteAccountErrorMessage {
                        Text(deleteAccountErrorMessage)
                            .foregroundStyle(.red)
                    }
                } else {
                    Section {
                        Text("Sign in or create an account to continue.")
                            .foregroundStyle(.secondary)
                        Button("Sign In / Create Account") {
                            isPresentingSignIn = true
                        }
                    }
                }

                if let signOutErrorMessage {
                    Section {
                        Text(signOutErrorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isPresentingSignIn) {
                SignInView()
            }
            .sheet(isPresented: $isPresentingMembership) {
                if let userID = accountState.currentUserID {
                    MembershipPaywallView(
                        userID: userID,
                        purchaseService: purchaseService,
                        claimWriter: claimWriter,
                        entitlementService: entitlementService
                    )
                }
            }
            .sheet(isPresented: $isPresentingDeleteConfirmation) {
                DeleteAccountConfirmationView {
                    isPresentingDeleteConfirmation = false
                    Task { await deleteAccount() }
                }
            }
            .onChange(of: accountState.pendingFamilyUserPromoOffer) { _, isPending in
                guard isPending else { return }
                isPresentingMembership = true
                accountState.pendingFamilyUserPromoOffer = false
            }
            .task(id: accountState.currentUserID) {
                fullNameDraft = accountState.currentUserDisplayName ?? ""
            }
        }
    }

    private func saveFullName() async {
        let trimmed = fullNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSavingName = true
        saveNameErrorMessage = nil
        defer { isSavingName = false }
        do {
            try await accountState.updateDisplayName(trimmed)
        } catch {
            saveNameErrorMessage = error.localizedDescription
        }
    }

    private func signOut() {
        do {
            try accountState.signOut()
            signOutErrorMessage = nil
        } catch {
            signOutErrorMessage = error.localizedDescription
        }
    }

    private func deleteAccount() async {
        guard let userID = accountState.currentUserID else { return }
        isDeletingAccount = true
        deleteAccountErrorMessage = nil
        defer { isDeletingAccount = false }
        do {
            try await AccountDeletionCoordinator.deleteAllData(
                for: userID,
                modelContext: modelContext,
                groupsService: groupsService,
                entitlementService: entitlementService
            )
            try await accountState.deleteAccount()
            activeCookbookState.reset()
            // No further navigation needed — AuthGatedRootView reacts to
            // accountState.isSignedIn becoming false and swaps to SignInView.
        } catch AccountDeletionError.blockedByAdminOnlyCookbooks(let cookbookNames) {
            let list = cookbookNames.joined(separator: ", ")
            deleteAccountErrorMessage = "You're the sole admin of \(list) — promote another admin or archive it from that cookbook's page before deleting your account."
        } catch AuthServiceError.requiresRecentLogin {
            deleteAccountErrorMessage = "For security, please sign out and sign back in, then try deleting your account again."
        } catch {
            deleteAccountErrorMessage = error.localizedDescription
        }
    }
}

private struct DeleteAccountConfirmationView: View {
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("This permanently deletes your account and everything tied to it — your personal recipes, cookbooks, and Family Cookbook memberships. This cannot be undone.")
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Type DELETE to confirm", text: $confirmationText)
                        #if os(iOS)
                        .textInputAutocapitalization(.characters)
                        #endif
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Delete Account")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        onConfirm()
                    }
                    .disabled(confirmationText != "DELETE")
                }
            }
        }
    }
}

#Preview {
    AccountView()
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
