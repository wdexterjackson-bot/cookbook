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
    @State private var locationCity = ""
    @State private var locationIsUS = true
    @State private var locationStateCode = ""
    @State private var locationCountry = ""
    @State private var savedLocation: UserLocation?
    @State private var isSavingLocation = false
    @State private var saveLocationErrorMessage: String?
    @State private var entitlement: Entitlement?
    @State private var isPresentingCreateFamilyCookbook = false
    @State private var isRedeemingTier1Credit = false
    @State private var isRedeemingAnnualCredit = false
    @State private var membershipActionMessage: String?
    @State private var membershipActionErrorMessage: String?
    @State private var discountCodeInput = ""
    @State private var isApplyingDiscountCode = false
    @State private var discountCodeMessage: String?
    @State private var discountCodeErrorMessage: String?

    private let purchaseService: PurchaseServicing = StoreKitPurchaseService()
    private let claimWriter: PurchaseClaimSubmitting = FirestorePurchaseClaimWriter()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()
    private let groupsService: GroupsServicing = FirestoreGroupsService()
    private let userProfileService: UserProfileServicing = FirestoreUserProfileService()
    private let publicationsService: PublicationsServicing = FirestorePublicationsService()

    var body: some View {
        NavigationStack {
            Form {
                if accountState.isSignedIn {
                    Section("Account") {
                        LabeledContent("Signed in", value: accountState.currentUserEmail ?? accountState.currentUserID ?? "")
                        LabeledContent("Name") {
                            TextField("Full Name", text: $fullNameDraft)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                #if os(iOS)
                                .textInputAutocapitalization(.words)
                                #endif
                                .onSubmit { Task { await saveFullName() } }
                        }
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
                        .buttonStyle(.borderedProminent)
                    }

                    Section {
                        LocationFieldsView(
                            city: $locationCity,
                            isUS: $locationIsUS,
                            stateCode: $locationStateCode,
                            country: $locationCountry
                        )
                        if locationHasUnsavedChanges {
                            Button("Save Location") {
                                Task { await saveLocation() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color.potluckTomato)
                            .disabled(isSavingLocation || locationCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        if let saveLocationErrorMessage {
                            Text(saveLocationErrorMessage).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Location")
                    } footer: {
                        Text("Optional. Used, along with your name, to credit who added a recipe — never shown elsewhere in the app.")
                    }

                    Section("Membership") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entitlement?.isProUser == true ? "Pro User" : "Standard User")
                                .font(.subheadline.weight(.semibold))
                            Button(entitlement?.isProUser == true ? "Purchases" : "Upgrade") {
                                isPresentingMembership = true
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 2)

                        // Hidden entirely at zero — an absent row reads
                        // cleaner than a credit count nobody can act on,
                        // same reasoning MembershipSummaryView already
                        // uses elsewhere. Not shown once already Pro —
                        // nothing left to spend it on.
                        if let tier1Credits = entitlement?.tier1Credits, tier1Credits > 0, entitlement?.isProUser != true {
                            membershipCreditRow(
                                title: "Pro User Credit",
                                count: tier1Credits,
                                expiresAt: entitlement?.tier1ExpiresAt,
                                isBusy: isRedeemingTier1Credit
                            ) {
                                Task { await useTier1Credit() }
                            }
                        }

                        // Hidden unless there's an awarded/available credit
                        // to use — this row says nothing about an already-
                        // active membership, only about an unspent credit.
                        if let annualCredits = entitlement?.annualProMembershipCredits, annualCredits > 0 {
                            membershipCreditRow(
                                title: "Annual Pro Membership",
                                count: annualCredits,
                                expiresAt: nil,
                                isBusy: isRedeemingAnnualCredit
                            ) {
                                Task { await useAnnualCredit() }
                            }
                        }

                        if let tier2Credits = entitlement?.tier2Credits, tier2Credits > 0 {
                            membershipCreditRow(
                                title: "Family Cookbook Credits",
                                count: tier2Credits,
                                expiresAt: entitlement?.tier2ExpiresAt,
                                isBusy: false
                            ) {
                                isPresentingCreateFamilyCookbook = true
                            }
                        }

                        if let membershipActionMessage {
                            Text(membershipActionMessage).foregroundStyle(.secondary).font(.caption)
                        }
                        if let membershipActionErrorMessage {
                            Text(membershipActionErrorMessage).foregroundStyle(.red).font(.caption)
                        }
                    }

                    Section {
                        TextField("Discount Code", text: $discountCodeInput)
                            #if os(iOS)
                            .textInputAutocapitalization(.characters)
                            #endif
                            .autocorrectionDisabled()
                        Button("Submit") {
                            Task { await applyDiscountCode() }
                        }
                        .disabled(isApplyingDiscountCode || discountCodeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if isApplyingDiscountCode {
                            ProgressView()
                        }
                        if let discountCodeMessage {
                            Text(discountCodeMessage).foregroundStyle(.green)
                        }
                        if let discountCodeErrorMessage {
                            Text(discountCodeErrorMessage).foregroundStyle(.red)
                        }
                    } header: {
                        Text("Discount Code")
                    } footer: {
                        Text("Have a code? Apply it here — an awarded credit shows up under Membership above.")
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
            .potluckHiddenScrollBackground()
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
            .sheet(isPresented: $isPresentingCreateFamilyCookbook) {
                CreateFamilyCookbookView(groupsService: groupsService)
            }
            .task(id: accountState.currentUserID) {
                fullNameDraft = accountState.currentUserDisplayName ?? ""
                await loadLocation()
                await loadEntitlement()
            }
            .onChange(of: isPresentingMembership) { wasPresenting, isPresenting in
                // The paywall sheet is where credits actually get spent —
                // refresh so this screen's own summary doesn't go stale.
                if wasPresenting, !isPresenting {
                    Task { await loadEntitlement() }
                }
            }
            .onChange(of: isPresentingCreateFamilyCookbook) { wasPresenting, isPresenting in
                // A tier-2 credit is only actually spent once the group is
                // successfully created (FirestoreGroupsService.createGroup's
                // own atomic transaction) — aborting the sheet without
                // saving leaves the credit untouched. Refreshing on close
                // either way just picks up whichever happened.
                if wasPresenting, !isPresenting {
                    Task { await loadEntitlement() }
                }
            }
        }
    }

    @ViewBuilder
    private func membershipCreditRow(title: String, count: Int, expiresAt: Date?, isBusy: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title) {
                if let expiresAt {
                    if expiresAt > .now {
                        Text("\(count) (expires \(expiresAt.formatted(date: .abbreviated, time: .omitted)))")
                    } else {
                        Text("\(count) (expired)")
                    }
                } else {
                    Text("\(count)")
                }
            }
            Button("Use Credit", action: action)
                .buttonStyle(.bordered)
                .disabled(isBusy)
        }
        .padding(.vertical, 2)
    }

    private func loadEntitlement() async {
        guard let userID = accountState.currentUserID else { return }
        entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
    }

    private func useTier1Credit() async {
        guard let userID = accountState.currentUserID else { return }
        isRedeemingTier1Credit = true
        membershipActionMessage = nil
        membershipActionErrorMessage = nil
        defer { isRedeemingTier1Credit = false }
        do {
            let redeemed = try await entitlementService.redeemTier1CreditForProUser(userID: userID)
            membershipActionMessage = redeemed ? "You're now a Pro User." : nil
            if !redeemed { membershipActionErrorMessage = "That credit isn't available anymore." }
            await loadEntitlement()
        } catch {
            membershipActionErrorMessage = error.localizedDescription
        }
    }

    private func useAnnualCredit() async {
        guard let userID = accountState.currentUserID else { return }
        isRedeemingAnnualCredit = true
        membershipActionMessage = nil
        membershipActionErrorMessage = nil
        defer { isRedeemingAnnualCredit = false }
        do {
            let redeemed = try await entitlementService.redeemAnnualProMembershipCredit(userID: userID)
            membershipActionMessage = redeemed ? "Your Annual Pro Membership is now active." : nil
            if !redeemed { membershipActionErrorMessage = "That credit isn't available anymore." }
            await loadEntitlement()
        } catch {
            membershipActionErrorMessage = error.localizedDescription
        }
    }

    private func applyDiscountCode() async {
        guard let userID = accountState.currentUserID else { return }
        isApplyingDiscountCode = true
        discountCodeMessage = nil
        discountCodeErrorMessage = nil
        defer { isApplyingDiscountCode = false }
        do {
            try await entitlementService.applyDiscountCode(discountCodeInput, userID: userID)
            discountCodeMessage = "Code applied — you have a new Annual Pro Membership credit."
            discountCodeInput = ""
            await loadEntitlement()
        } catch EntitlementServiceError.invalidDiscountCode {
            discountCodeErrorMessage = "That code isn't valid."
        } catch EntitlementServiceError.discountCodeAlreadyRedeemed {
            discountCodeErrorMessage = "You've already used that code."
        } catch {
            discountCodeErrorMessage = error.localizedDescription
        }
    }

    /// The single source of truth for "what would saving right now write" —
    /// used by both locationHasUnsavedChanges and saveLocation() so they
    /// can never drift apart. They used to build this independently, and
    /// did diverge: this version trims+nils out an empty stateCode/country,
    /// but locationHasUnsavedChanges's old copy left stateCode as a raw
    /// (untrimmed, non-nil'd) empty string. For a US location with no
    /// state selected, that meant the just-saved value (stateCode: nil)
    /// never compared equal to the freshly-rebuilt draft (stateCode: ""),
    /// so "Save Location" never disappeared and reappeared on every
    /// reopen — reading as "my location never actually saved" even though
    /// it had.
    private var currentDraftLocation: UserLocation {
        let trimmedCountry = locationCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        return UserLocation(
            city: locationCity.trimmingCharacters(in: .whitespacesAndNewlines),
            isUS: locationIsUS,
            stateCode: locationIsUS ? (locationStateCode.isEmpty ? nil : locationStateCode) : nil,
            country: locationIsUS ? nil : (trimmedCountry.isEmpty ? nil : trimmedCountry)
        )
    }

    private var locationHasUnsavedChanges: Bool {
        currentDraftLocation != (savedLocation ?? UserLocation(city: "", isUS: true, stateCode: nil, country: nil))
    }

    private func loadLocation() async {
        guard let userID = accountState.currentUserID else { return }
        guard let location = try? await userProfileService.fetchLocation(userID: userID) else { return }
        savedLocation = location
        locationCity = location.city
        locationIsUS = location.isUS
        locationStateCode = location.stateCode ?? ""
        locationCountry = location.country ?? ""
    }

    private func saveLocation() async {
        guard let userID = accountState.currentUserID else { return }
        let location = currentDraftLocation
        guard !location.city.isEmpty else { return }
        isSavingLocation = true
        saveLocationErrorMessage = nil
        defer { isSavingLocation = false }
        do {
            try await userProfileService.setLocation(location, userID: userID)
            savedLocation = location
        } catch {
            saveLocationErrorMessage = error.localizedDescription
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
                entitlementService: entitlementService,
                userProfileService: userProfileService,
                publicationsService: publicationsService
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
