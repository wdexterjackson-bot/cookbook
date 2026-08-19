//
//  CreateFamilyCookbookView.swift
//  cookbook
//
//  Two destinations: create a new group (with its first cookbook,
//  spending a tier-2 credit) or add a further cookbook to a group the
//  user already administers (free — GroupsServicing.createGroupCookbook,
//  the founder already paid for the group itself). The existing-group
//  choice only appears at all when the user actually has ≥1 admin
//  membership. Multiple groups (and multiple cookbooks per group) are
//  allowed; there's no uniqueness requirement on any of these fields.
//

import SwiftUI

private enum CreationDestination: String, CaseIterable, Identifiable {
    case newGroup = "New Community"
    case existingGroup = "Existing Community"
    var id: String { rawValue }
}

struct CreateFamilyCookbookView: View {
    let groupsService: GroupsServicing

    @Environment(AccountState.self) private var accountState
    @Environment(\.dismiss) private var dismiss

    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()
    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    @State private var gate = EntitlementGateCoordinator()

    @State private var adminGroups: [FamilyGroup] = []
    @State private var destination: CreationDestination = .newGroup
    @State private var selectedExistingGroupID: String?

    @State private var cookbookName = ""
    @State private var familyName = ""
    @State private var locationText = ""
    /// Private by default — a Family Cookbook is invite/request-only
    /// unless the creator explicitly opts into public search.
    @State private var isPublic = false
    /// On by default — matches the behavior every Family Cookbook had
    /// before this toggle existed, where any member could publish. Off
    /// is for a curated, read-only cookbook (e.g. a seed cookbook only
    /// admins add to).
    @State private var allowsMemberPublishing = true
    @State private var approvalPolicy: JoinApprovalPolicy = .anyAdministrator
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var idempotencyKey = UUID().uuidString

    var body: some View {
        NavigationStack {
            Form {
                if !adminGroups.isEmpty {
                    Section {
                        Picker("Add To", selection: $destination) {
                            ForEach(CreationDestination.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)

                        if destination == .existingGroup {
                            Picker("Community Cookbook", selection: $selectedExistingGroupID) {
                                Text("Choose a Community Cookbook").tag(String?.none)
                                ForEach(adminGroups) { group in
                                    Text(group.name).tag(String?.some(group.id))
                                }
                            }
                        }
                    }
                }

                Section("Cookbook") {
                    TextField("Cookbook Name (e.g. Jackson Family Reunion 2020)", text: $cookbookName)
                }

                if destination == .newGroup {
                    Section("Family / Group") {
                        TextField("Family, Group, or Company Name (e.g. Jackson)", text: $familyName)
                        TextField("Home Location (e.g. Baltimore, MD)", text: $locationText)
                            .autocorrectionDisabled()
                    }

                    Section {
                        Toggle("Publicly searchable", isOn: $isPublic)
                    } footer: {
                        Text("Private cookbooks are only found by invitation or a join request someone approves.")
                    }

                    Section {
                        Picker("Who Can Join", selection: $approvalPolicy) {
                            Text("Only Me").tag(JoinApprovalPolicy.creatorOnly)
                            Text("Any Administrator").tag(JoinApprovalPolicy.anyAdministrator)
                            Text("Any Member").tag(JoinApprovalPolicy.anyUser)
                            Text("Anyone, Instantly").tag(JoinApprovalPolicy.noApprovalNeeded)
                        }
                    } footer: {
                        Text(approvalPolicyDescription)
                    }
                }

                Section {
                    Toggle("Members can publish recipes here", isOn: $allowsMemberPublishing)
                } footer: {
                    Text("Off makes this a read-only cookbook — only admins can add recipes to it, even after others join.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle(destination == .newGroup ? "Create a Community Cookbook" : "Add a Cookbook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(destination == .newGroup ? "Create" : "Add") {
                        Task { await attemptCreate() }
                    }
                    .disabled(!canSubmit || isBusy)
                }
            }
            .task {
                await loadAdminGroups()
            }
        }
        .entitlementGate(
            gate,
            userID: accountState.currentUserID ?? "",
            entitlementService: entitlementService,
            purchaseService: purchaseService,
            claimWriter: claimWriter
        )
    }

    private var approvalPolicyDescription: String {
        switch approvalPolicy {
        case .creatorOnly:
            return "Only you can approve join requests."
        case .anyAdministrator:
            return "Any administrator can approve join requests — the normal setting for a community cookbook."
        case .anyUser:
            return "Any member, not just admins, can approve join requests."
        case .noApprovalNeeded:
            return "Anyone can join instantly, without approval — meant for a cookbook you want genuinely open to everyone, not a typical community cookbook."
        }
    }

    private var canSubmit: Bool {
        guard !cookbookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        switch destination {
        case .newGroup:
            return !familyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !locationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existingGroup:
            return selectedExistingGroupID != nil
        }
    }

    private func loadAdminGroups() async {
        guard let userID = accountState.currentUserID else { return }
        let memberships = (try? await groupsService.fetchMemberships(forUser: userID))?
            .filter { $0.status == .active && $0.role == .admin } ?? []
        var groups: [FamilyGroup] = []
        for membership in memberships {
            if let group = try? await groupsService.fetchGroup(id: membership.groupID) {
                groups.append(group)
            }
        }
        adminGroups = groups
    }

    private func attemptCreate() async {
        guard let userID = accountState.currentUserID else { return }
        switch destination {
        case .newGroup:
            let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
            await gate.attempt(
                .groupCreation,
                outcome: EntitlementGate.forGroupCreation(entitlement),
                recheck: { EntitlementGate.forGroupCreation($0) }
            ) {
                await createNewGroup(userID: userID)
            }
        case .existingGroup:
            await addCookbookToExistingGroup(userID: userID)
        }
    }

    private func createNewGroup(userID: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let groupDetails = NewGroupDetails(
            name: familyName.trimmingCharacters(in: .whitespacesAndNewlines),
            description: "",
            type: "Family",
            locationText: locationText.trimmingCharacters(in: .whitespacesAndNewlines),
            structuredRegion: nil,
            visibility: isPublic ? .publicGroup : .privateGroup,
            allowsMemberInvites: false,
            approvalPolicy: approvalPolicy
        )
        let cookbookDetails = NewGroupCookbookDetails(
            cookbookName: cookbookName.trimmingCharacters(in: .whitespacesAndNewlines),
            allowsMemberPublishing: allowsMemberPublishing
        )

        do {
            _ = try await groupsService.createGroup(
                groupDetails,
                cookbookDetails: cookbookDetails,
                creatorUserID: userID,
                creatorDisplayName: accountState.currentUserDisplayName ?? "",
                idempotencyKey: idempotencyKey
            )
            dismiss()
        } catch GroupsServiceError.insufficientCredits {
            errorMessage = "You don't have a Community Cookbook creation credit available."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addCookbookToExistingGroup(userID: String) async {
        guard let groupID = selectedExistingGroupID else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let cookbookDetails = NewGroupCookbookDetails(
            cookbookName: cookbookName.trimmingCharacters(in: .whitespacesAndNewlines),
            allowsMemberPublishing: allowsMemberPublishing
        )

        do {
            _ = try await groupsService.createGroupCookbook(
                cookbookDetails,
                in: groupID,
                creatorUserID: userID,
                creatorDisplayName: accountState.currentUserDisplayName ?? ""
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    CreateFamilyCookbookView(groupsService: InMemoryGroupsService())
        .environment(AccountState(authService: FakeAuthService()))
}
