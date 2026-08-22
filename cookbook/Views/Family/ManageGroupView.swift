//
//  ManageGroupView.swift
//  cookbook
//
//  Reached from Administrator > Manage Groups. Group-level settings only
//  — name, location, who can join, invites, visibility — shared by every
//  cookbook the group holds. Cookbook-specific settings (cookbook name,
//  member publishing, comments ceiling) live one level down, in
//  CommunityCookbookManageView instead, reached from Administrator >
//  Manage Community Cookbooks. Leaving/deleting is inherently a group-wide
//  action (GroupsServicing.leaveGroup takes a groupID, not a cookbookID),
//  so it lives here, not on any individual cookbook's screen.
//

import SwiftUI

struct ManageGroupView: View {
    let group: FamilyGroup
    let membership: Membership
    let groupsService: GroupsServicing

    @Environment(\.dismiss) private var dismiss

    @State private var groupMemberships: [Membership] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isPresentingLeaveConfirmation = false
    @State private var isPresentingGroupQRCode = false

    @State private var groupName: String
    @State private var locationText: String
    @State private var isPublic: Bool
    @State private var approvalPolicy: JoinApprovalPolicy
    @State private var allowsMemberInvites: Bool
    @State private var isSaving = false
    @State private var validationMessage: String?

    private var isAdmin: Bool { membership.role == .admin }

    init(group: FamilyGroup, membership: Membership, groupsService: GroupsServicing) {
        self.group = group
        self.membership = membership
        self.groupsService = groupsService
        _groupName = State(initialValue: group.name)
        _locationText = State(initialValue: group.locationText)
        _isPublic = State(initialValue: group.visibility == .publicGroup)
        _approvalPolicy = State(initialValue: group.approvalPolicy)
        _allowsMemberInvites = State(initialValue: group.allowsMemberInvites)
    }

    var body: some View {
        List {
            Section {
                groupHeader
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Location", value: group.locationText)
                LabeledContent("Your Role", value: membership.role.rawValue.capitalized)
                LabeledContent("Visibility", value: group.visibility == .publicGroup ? "Public" : "Private")
                Button {
                    isPresentingGroupQRCode = true
                } label: {
                    Label("Share Group QR Code", systemImage: "qrcode")
                }
                if isAdmin {
                    NavigationLink {
                        GroupAdminManagementView(group: group, groupsService: groupsService)
                    } label: {
                        Label("Manage Administrators", systemImage: "person.badge.key")
                    }
                }
            }

            if isAdmin {
                Section {
                    TextField("Family, Group, or Company Name", text: $groupName)
                    TextField("Home Location (e.g. Baltimore, MD)", text: $locationText)
                        .autocorrectionDisabled()
                    Toggle("Publicly searchable", isOn: $isPublic)
                    Picker("Who Can Join", selection: $approvalPolicy) {
                        Text("Only Me").tag(JoinApprovalPolicy.creatorOnly)
                        Text("Any Administrator").tag(JoinApprovalPolicy.anyAdministrator)
                        Text("Any Member").tag(JoinApprovalPolicy.anyUser)
                        Text("Anyone, Instantly").tag(JoinApprovalPolicy.noApprovalNeeded)
                    }
                    Toggle("Members can invite others", isOn: $allowsMemberInvites)
                    if let validationMessage {
                        Text(validationMessage).foregroundStyle(.red)
                    }
                    Button(isSaving ? "Saving…" : "Save Group Settings") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                } header: {
                    Text("Group Settings")
                } footer: {
                    Text("These apply to every Community Cookbook this group holds.")
                }
            }

            Section {
                Button(isLastActiveMember ? "Delete Group" : "Leave Group", role: .destructive) {
                    isPresentingLeaveConfirmation = true
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadMemberships()
        }
        .confirmationDialog(
            leaveConfirmationMessage,
            isPresented: $isPresentingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button(isLastActiveMember ? "Delete Group" : "Leave", role: .destructive) {
                Task { await leave() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingGroupQRCode) {
            QRCodeDisplayView(
                payload: .group(id: group.id),
                title: group.name,
                subtitle: "Scan this to send a request to join \(group.name)."
            )
        }
    }

    private var isLastActiveMember: Bool {
        GroupPolicy.isLastActiveMember(membership.userID, in: groupMemberships)
    }

    private var leaveConfirmationMessage: String {
        if isLastActiveMember {
            return "You're the last member of \(group.name). Leaving will permanently delete this group and everything in it — every cookbook, recipe, and photo — for everyone. This cannot be undone."
        }
        return "Leave \(group.name)? You'll be removed from every Community Cookbook this group holds."
    }

    private var groupHeader: some View {
        VStack(spacing: 8) {
            Text(group.name)
                .font(.potluckHeadline(24))
                .foregroundStyle(Color.potluckDeepTeal)
                .multilineTextAlignment(.center)

            if let urlString = group.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.secondary.opacity(0.1)
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
            }
        }
        .padding(.vertical, 4)
    }

    private func save() async {
        let trimmedName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = locationText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedLocation.isEmpty else {
            validationMessage = "Give your Community a name and a location."
            return
        }
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await groupsService.updateGroup(
                group.id, name: trimmedName, locationText: trimmedLocation,
                visibility: isPublic ? .publicGroup : .privateGroup,
                approvalPolicy: approvalPolicy, allowsMemberInvites: allowsMemberInvites,
                actingUserID: membership.userID
            )
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func loadMemberships() async {
        groupMemberships = (try? await groupsService.fetchMemberships(forGroup: group.id)) ?? []
    }

    private func leave() async {
        do {
            try await groupsService.leaveGroup(groupID: group.id, userID: membership.userID)
            dismiss()
        } catch GroupsServiceError.lastAdminCannotLeaveOrBeDemoted {
            errorMessage = "You're the last admin of this group with other active members still in it — promote someone else first."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
