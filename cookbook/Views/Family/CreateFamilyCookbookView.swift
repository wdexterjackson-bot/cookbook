//
//  CreateFamilyCookbookView.swift
//  cookbook
//
//  Cookbook Name + Family/Group Name + Home Location, together, must be
//  unique (FamilyGroup.uniquenessKey, enforced by GroupsServicing +
//  firestore.rules) — GroupsServiceError.duplicateCookbookIdentity is
//  surfaced here as a clear, actionable message rather than a raw
//  Firestore failure.
//

import SwiftUI

struct CreateFamilyCookbookView: View {
    let groupsService: GroupsServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss

    @State private var cookbookName = ""
    @State private var familyName = ""
    @State private var locationText = ""
    /// Private by default — a Family Cookbook is invite/request-only
    /// unless the creator explicitly opts into public search.
    @State private var isPublic = false
    /// On by default — matches the behavior every Family Cookbook had
    /// before this toggle existed, where any member could publish. Off
    /// is for a curated, read-only cookbook (e.g. a seed cookbook only
    /// the creator adds to).
    @State private var allowsMemberPublishing = true
    /// Off by default — joining still goes through the normal
    /// request/approve flow. On skips approval entirely, meant for a
    /// small number of intentionally open cookbooks (e.g. one global
    /// cookbook everyone's invited to), not typical family use.
    @State private var autoApproveJoinRequests = false
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var idempotencyKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                Section("Family Cookbook") {
                    TextField("Cookbook Name (e.g. Jackson Family Reunion 2020)", text: $cookbookName)
                    TextField("Family, Group, or Company Name (e.g. Jackson)", text: $familyName)
                    TextField("Home Location (e.g. Baltimore, MD)", text: $locationText)
                        .autocorrectionDisabled()
                }

                Section {
                    Toggle("Publicly searchable", isOn: $isPublic)
                } footer: {
                    Text("Private cookbooks are only found by invitation or a join request you approve.")
                }

                Section {
                    Toggle("Anyone can join instantly", isOn: $autoApproveJoinRequests)
                } footer: {
                    Text("Off means you approve each join request yourself, like a normal Family Cookbook. On skips that — meant for a cookbook you want genuinely open to everyone, not a typical family group.")
                }

                Section {
                    Toggle("Members can publish recipes here", isOn: $allowsMemberPublishing)
                } footer: {
                    Text("Off makes this a read-only cookbook — only you can add recipes to it, even after others join.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle("Create a Family Cookbook")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await create() }
                    }
                    .disabled(!canSubmit || isBusy)
                }
            }
        }
    }

    private var canSubmit: Bool {
        !cookbookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() async {
        guard let userID = accountState.currentUserID else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let details = NewGroupDetails(
            name: familyName.trimmingCharacters(in: .whitespacesAndNewlines),
            cookbookName: cookbookName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: "",
            type: "Family",
            locationText: locationText.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredRegion: nil,
            visibility: isPublic ? .publicGroup : .privateGroup,
            allowsMemberInvites: false,
            allowsMemberPublishing: allowsMemberPublishing,
            autoApproveJoinRequests: autoApproveJoinRequests
        )

        do {
            _ = try await groupsService.createGroup(details, creatorUserID: userID, idempotencyKey: idempotencyKey)
            dismiss()
        } catch GroupsServiceError.duplicateCookbookIdentity {
            errorMessage = "A Family Cookbook with this Cookbook Name, Family/Group Name, and Location already exists — try a different combination."
        } catch GroupsServiceError.insufficientCredits {
            errorMessage = "You don't have a Family Cookbook creation credit available."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    CreateFamilyCookbookView(groupsService: InMemoryGroupsService())
        .environment(AccountState(authService: FakeAuthService()))
}
