//
//  CommunityCookbookManageView.swift
//  cookbook
//
//  Reached from Administrator > Manage Community Cookbooks — cookbook-only
//  settings (name, member publishing, comments ceiling, and cover
//  color/style/image — the same three-way cover controls
//  CookbookConfigurationView offers a personal cookbook, since there was
//  previously no way at all for a Community Cookbook's admin/creator to
//  set one). Group-level settings (name, location, who can join, invites)
//  and group-wide actions (Share QR, Manage Administrators, Leave/Delete)
//  live one level up, on ManageGroupView instead (Administrator > Manage
//  Groups) — a group can hold several cookbooks, so those only make sense
//  once per group, not once per cookbook. Shows no recipes at all (see
//  CommunityCookbookRecipesView, the Cookbooks tab's destination, for
//  that).
//

import SwiftUI
#if os(iOS)
import PhotosUI
import UIKit
#endif

struct CommunityCookbookManageView: View {
    let group: FamilyGroup
    let cookbook: GroupCookbook
    let membership: Membership
    let groupsService: GroupsServicing

    @Environment(AccountState.self) private var accountState

    @State private var cookbookName: String
    @State private var allowsMemberPublishing: Bool
    @State private var commentsAllowed: Bool
    @State private var coverColorHex: String
    /// Priority for the cover actually shown is coverImageURL >
    /// coverStyleImageName > coverColorHex, same as Cookbook's own
    /// personal-cookbook cover priority.
    @State private var coverStyleImageName: String?
    /// Non-nil only once the user picks a NEW photo this session — unlike
    /// Cookbook.coverImageFilename, there's no local file cache for a
    /// Community Cookbook's cover, so the *existing* cover is always
    /// shown straight from cookbook.coverImageURL until this is set.
    @State private var coverImageData: Data?
    @State private var removesExistingCoverImage = false
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    @State private var isSaving = false
    @State private var validationMessage: String?
    @State private var entitlement: Entitlement?

    private let photoUploadService: GroupCookbookPhotoUploadServicing = FirebaseGroupCookbookPhotoUploadService()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()

    private var isAdmin: Bool { membership.role == .admin }

    /// A Community Cookbook is always cloud-synced (there's no local-only
    /// mode for one), so this is just the Annual Pro check on its own —
    /// unlike CookbookConfigurationView's personal-cookbook equivalent,
    /// there's no "isCloudSynced" condition to also check here.
    private var coverImageRequiresAnnualProMembership: Bool {
        entitlement?.isActiveAnnualProMember != true
    }

    init(group: FamilyGroup, cookbook: GroupCookbook, membership: Membership, groupsService: GroupsServicing) {
        self.group = group
        self.cookbook = cookbook
        self.membership = membership
        self.groupsService = groupsService
        _cookbookName = State(initialValue: cookbook.cookbookName)
        _allowsMemberPublishing = State(initialValue: cookbook.allowsMemberPublishing)
        _commentsAllowed = State(initialValue: cookbook.commentsAllowed ?? true)
        _coverColorHex = State(initialValue: cookbook.coverColorHex ?? Cookbook.defaultColorHex)
        _coverStyleImageName = State(initialValue: cookbook.coverStyleImageName)
    }

    var body: some View {
        List {
            Section {
                cookbookHeader
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                LabeledContent("Community", value: group.name)
                LabeledContent("Your Role", value: membership.role.rawValue.capitalized)
                Toggle("Sync to Cloud", isOn: .constant(true))
                    .disabled(true)
                if !isAdmin {
                    LabeledContent("Members Can Publish", value: cookbook.allowsMemberPublishing ? "Yes" : "No")
                    LabeledContent("Comments Allowed", value: (cookbook.commentsAllowed ?? true) ? "Yes" : "No")
                }
            } footer: {
                Text("Community Cookbooks always live in the cloud so every member can see them — this can't be turned off.")
            }

            if isAdmin {
                Section {
                    TextField("Cookbook Name", text: $cookbookName)
                    Toggle("Members can publish recipes here", isOn: $allowsMemberPublishing)
                    Toggle("Allow comments on recipes in this cookbook", isOn: $commentsAllowed)
                } header: {
                    Text("Cookbook Settings")
                } footer: {
                    Text("Recipe owners can still turn comments off for their own recipe. Turning this off blocks comments cookbook-wide, even for recipes that already had them on.")
                }

                Section("Cover Color") {
                    colorSwatchGrid
                    #if os(iOS)
                    ColorPicker("Custom Color", selection: Binding(
                        get: { Color(hex: coverColorHex) },
                        set: { coverColorHex = $0.hexString }
                    ))
                    #endif
                }

                Section {
                    coverStyleGrid
                } header: {
                    Text("Cover Style")
                } footer: {
                    Text("A ready-made design instead of a plain color. A custom cover image (below) always takes priority over a style if you add one.")
                }

                #if os(iOS)
                Section {
                    coverImagePicker
                } header: {
                    Text("Cover Image")
                } footer: {
                    Text("Uploading a custom cover photo for a Community Cookbook requires an active Annual Pro Membership.")
                }
                #endif

                Section {
                    if let validationMessage {
                        Text(validationMessage).foregroundStyle(.red)
                    }
                    Button(isSaving ? "Saving…" : "Save Cookbook Settings") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await loadEntitlement()
        }
    }

    private func loadEntitlement() async {
        guard let userID = accountState.currentUserID else {
            entitlement = nil
            return
        }
        entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
    }

    private var cookbookHeader: some View {
        VStack(spacing: 8) {
            Text(cookbook.cookbookName)
                .font(.potluckHeadline(24))
                .foregroundStyle(Color.potluckDeepTeal)
                .multilineTextAlignment(.center)

            coverArt
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
        }
        .padding(.vertical, 4)
    }

    /// Priority: a custom uploaded image wins; otherwise a chosen Cover
    /// Style; otherwise the plain color — same fallback order
    /// RecipeListView's personal-cookbook header uses.
    @ViewBuilder
    private var coverArt: some View {
        if let urlString = cookbook.coverImageURL ?? group.coverImageURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.1)
            }
        } else if let styleName = cookbook.coverStyleImageName, let style = CookbookCoverStyleCatalog.style(named: styleName) {
            Image(style.imageAssetName)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color(hex: cookbook.coverColorHex ?? Cookbook.defaultColorHex)
        }
    }

    private var colorSwatchGrid: some View {
        HStack(spacing: 12) {
            ForEach(CookbookConfigurationView.curatedColorHexes, id: \.self) { hex in
                Button {
                    coverColorHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay {
                            if coverColorHex.caseInsensitiveCompare(hex) == .orderedSame {
                                Circle().strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Color swatch \(hex)")
                .accessibilityAddTraits(coverColorHex.caseInsensitiveCompare(hex) == .orderedSame ? [.isSelected] : [])
            }
        }
    }

    private var coverStyleGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Button {
                    coverStyleImageName = nil
                } label: {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .foregroundStyle(.secondary)
                        .frame(width: 72, height: 72)
                        .overlay {
                            Text("None")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .overlay {
                            if coverStyleImageName == nil {
                                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("No cover style")
                .accessibilityAddTraits(coverStyleImageName == nil ? [.isSelected] : [])

                ForEach(CookbookCoverStyleCatalog.allStyles) { style in
                    Button {
                        coverStyleImageName = style.imageAssetName
                    } label: {
                        Image(style.imageAssetName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay {
                                if coverStyleImageName == style.imageAssetName {
                                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary, lineWidth: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style.displayName)
                    .accessibilityAddTraits(coverStyleImageName == style.imageAssetName ? [.isSelected] : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    #if os(iOS)
    @ViewBuilder
    private var coverImagePicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            if let coverImageData, let uiImage = UIImage(data: coverImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else if !removesExistingCoverImage, let urlString = cookbook.coverImageURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView()
                }
                .frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Label("Add Cover Image", systemImage: "photo")
            }
        }
        .accessibilityLabel(coverImageData == nil && cookbook.coverImageURL == nil ? "Add cover image" : "Change cover image")
        .disabled(coverImageRequiresAnnualProMembership)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    coverImageData = data
                    removesExistingCoverImage = false
                }
            }
        }

        if coverImageData != nil || (cookbook.coverImageURL != nil && !removesExistingCoverImage) {
            Button("Remove Cover Image", role: .destructive) {
                coverImageData = nil
                selectedPhotoItem = nil
                removesExistingCoverImage = true
            }
        }
    }
    #endif

    private func save() async {
        let trimmed = cookbookName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationMessage = "Give this cookbook a name."
            return
        }
        validationMessage = nil
        isSaving = true
        defer { isSaving = false }

        var resolvedCoverImageURL = cookbook.coverImageURL

        #if os(iOS)
        if let coverImageData {
            guard let userID = accountState.currentUserID else { return }
            let entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
            guard entitlement?.isActiveAnnualProMember == true else {
                validationMessage = "Uploading a custom cover photo for a Community Cookbook requires an active Annual Pro Membership."
                return
            }
            do {
                resolvedCoverImageURL = try await photoUploadService.upload(imageData: coverImageData, groupID: group.id, cookbookID: cookbook.id).absoluteString
            } catch {
                validationMessage = "Couldn't upload the cover photo: \(error.localizedDescription)"
                return
            }
        } else if removesExistingCoverImage {
            // Best-effort — an orphaned Storage file is a minor cost, not
            // worth blocking the save the user actually asked for.
            try? await photoUploadService.delete(groupID: group.id, cookbookID: cookbook.id)
            resolvedCoverImageURL = nil
        }
        #endif

        do {
            try await groupsService.updateGroupCookbook(
                cookbook.id, groupID: group.id, cookbookName: trimmed,
                allowsMemberPublishing: allowsMemberPublishing, commentsAllowed: commentsAllowed,
                coverColorHex: coverColorHex, coverStyleImageName: coverStyleImageName, coverImageURL: resolvedCoverImageURL,
                actingUserID: membership.userID
            )
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}
