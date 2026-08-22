//
//  CookbookConfigurationView.swift
//  cookbook
//
//  Create and edit share this one screen, same pattern as
//  CreateEditRecipeView. Nothing here is mandatory — every field has a
//  sensible default — so a first-run user can tap Done immediately
//  without configuring anything, matching the app's existing
//  no-friction-for-personal-use principle.
//

import SwiftUI
import SwiftData
#if os(iOS)
import PhotosUI
#endif

struct CookbookConfigurationView: View {
    enum Mode {
        case create(ownerID: String)
        case edit(Cookbook)
    }

    static let curatedColorHexes = [
        "C25432", // terracotta
        "2F6B4F", // forest green
        "D4A017", // mustard
        "34495E", // navy
        "6B4E71", // plum
        "2A7F7E", // teal
        "B33A3A", // brick
        "4A4A4A", // charcoal
    ]

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    /// Only consulted in `.create` mode, to avoid silently handing out a
    /// second "My Cookbook" — see `clearDefaultTitleIfAlreadyTaken()`.
    /// Unused in `.edit` mode.
    @Query(sort: \Cookbook.sortOrder) private var allCookbooks: [Cookbook]

    private let syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService()
    private let photoUploadService: PersonalCookbookPhotoUploadServicing = FirebasePersonalCookbookPhotoUploadService()
    private let entitlementService: EntitlementServicing = FirestoreEntitlementService()

    @State private var title: String
    @State private var coverColorHex: String
    /// Priority for the cover actually shown is coverImageFilename >
    /// coverStyleImageName > coverColorHex — a custom photo always wins,
    /// a chosen style beats plain color, color is the universal fallback.
    @State private var coverStyleImageName: String?
    @State private var coverImageData: Data?
    @State private var removesExistingCoverImage = false
    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    /// One ordered list for every chapter currently included — whether it
    /// came from a catalog toggle or the custom-name field — so the two
    /// can be freely reordered together instead of always showing catalog
    /// chapters first. Display/save order is exactly this array's order.
    @State private var chapterTitles: [String]
    /// Keyed by chapter title, same as chapterTitles/existingSectionsByTitle
    /// in save() below — a title with no entry here just shows the
    /// generic placeholder, not an error. Populated automatically with
    /// CookbookSectionIconCatalog's matching full-color icon the moment a
    /// chapter is added (see addChapter(_:)); the "Change" action can
    /// reassign to any icon, full-color or black.
    @State private var chapterIcons: [String: String]
    /// Drives SectionIconPickerView's presentation — the title of whichever
    /// chapter's "Change" button was tapped, nil when no picker is open.
    @State private var chapterTitlePendingIconChange: String?
    /// Flips to true the moment the user actually drags to reorder (not
    /// from adding/removing a chapter) — see Cookbook.chaptersManuallyReordered.
    @State private var chaptersManuallyReordered: Bool
    @State private var newCustomSectionTitle = ""
    /// Set by `clearDefaultTitleIfAlreadyTaken()` the moment it blanks the
    /// default title out — drives the Title section's footer prompt. Never
    /// set in `.edit` mode.
    @State private var titleWasClearedDueToCollision = false
    @State private var validationMessage: String?
    @State private var isCloudSynced: Bool
    /// Captured at open time so save() can tell "just turned on this
    /// session" (which pushes immediately, per the confirmed decision that
    /// there's never a window where the toggle says on but no cloud copy
    /// exists) apart from "was already on, editing something else" (which
    /// must NOT push — sync stays tied to the explicit Back Up action for
    /// every other edit, matching the "manual, not continuous" design).
    private let initialIsCloudSynced: Bool
    @State private var lastSyncedAt: Date?
    @State private var isSyncing = false
    @State private var syncErrorMessage: String?
    @State private var entitlement: Entitlement?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "My Cookbook")
            _coverColorHex = State(initialValue: Cookbook.defaultColorHex)
            _coverStyleImageName = State(initialValue: nil)
            _coverImageData = State(initialValue: nil)
            _chapterTitles = State(initialValue: [])
            _chapterIcons = State(initialValue: [:])
            _chaptersManuallyReordered = State(initialValue: false)
            _isCloudSynced = State(initialValue: false)
            initialIsCloudSynced = false
            _lastSyncedAt = State(initialValue: nil)

        case .edit(let cookbook):
            _title = State(initialValue: cookbook.title)
            _coverColorHex = State(initialValue: cookbook.coverColorHex)
            _coverStyleImageName = State(initialValue: cookbook.coverStyleImageName)
            if let filename = cookbook.coverImageFilename {
                _coverImageData = State(initialValue: PhotoStore.data(for: filename))
            } else {
                _coverImageData = State(initialValue: nil)
            }

            let sortedSections = cookbook.sections.sorted { $0.sortOrder < $1.sortOrder }
            _chapterTitles = State(initialValue: sortedSections.map(\.title))
            _chapterIcons = State(initialValue: Dictionary(
                sortedSections.compactMap { section in section.iconAssetName.map { (section.title, $0) } },
                uniquingKeysWith: { _, latest in latest }
            ))
            _chaptersManuallyReordered = State(initialValue: cookbook.chaptersManuallyReordered)
            _isCloudSynced = State(initialValue: cookbook.isCloudSynced)
            initialIsCloudSynced = cookbook.isCloudSynced
            _lastSyncedAt = State(initialValue: cookbook.lastSyncedAt)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Cookbook Title", text: $title)
                } header: {
                    Text("Title")
                } footer: {
                    if titleWasClearedDueToCollision {
                        Text("You already have a cookbook named \"My Cookbook\" — give this one its own name.")
                    }
                }

                Section {
                    Toggle("Sync to Cloud", isOn: $isCloudSynced)
                    if isCloudSynced {
                        LabeledContent("Last Synced") {
                            if let lastSyncedAt {
                                Text(lastSyncedAt, style: .relative)
                            } else {
                                Text("Never")
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("On-device only by default. When on, tap Back Up any time to push the latest copy to the cloud — Restore from Cloud pulls it down on another device. Nothing syncs automatically.")
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
                    if coverImageRequiresAnnualProMembership {
                        Text("This cookbook is synced to the cloud, so adding a cover image requires an active Annual Pro Membership.")
                    }
                }
                #endif

                Section {
                    ForEach(RecipeSectionCatalog.defaultChapterTitles, id: \.self) { catalogTitle in
                        Toggle(catalogTitle, isOn: catalogBinding(for: catalogTitle))
                    }
                } header: {
                    Text("Chapters")
                } footer: {
                    Text("Choose as many or as few as you'd like — recipes without a chapter still show up in one flat list.")
                }

                Section {
                    ForEach(chapterTitles, id: \.self) { title in
                        chapterOrderRow(title)
                    }
                    .onDelete { offsets in
                        chapterTitles.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        chapterTitles.move(fromOffsets: from, toOffset: to)
                        chaptersManuallyReordered = true
                    }
                    .alwaysEditingOnIOS()

                    HStack {
                        TextField("Other (custom chapter name)", text: $newCustomSectionTitle)
                            .onSubmit(addCustomSection)
                        Button("Add", action: addCustomSection)
                            .disabled(newCustomSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Chapter Order")
                } footer: {
                    Text("Drag to reorder — this is the order chapters will appear in when viewing the cookbook. Swipe to remove.")
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
                if isSyncing {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Syncing to the cloud…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .navigationTitle(isEditing ? "Edit Cookbook" : "New Cookbook")
            .onAppear(perform: clearDefaultTitleIfAlreadyTaken)
            .task {
                await loadEntitlement()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        Task { await saveAndSync() }
                    }
                    .disabled(isSyncing)
                }
            }
            .alert(
                "Couldn't Sync to the Cloud",
                isPresented: Binding(
                    get: { syncErrorMessage != nil },
                    set: { if !$0 { syncErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text((syncErrorMessage ?? "") + " Your cookbook was still saved locally — try Back Up again later.")
            }
            // Attached to the Form itself, not nested inside the Chapter
            // Order Section/List content above — a sheet attached to
            // content nested inside a List is unreliable in SwiftUI (see
            // the ingredient Amount wheel-picker fix for the same lesson
            // learned the hard way).
            .sheet(isPresented: Binding(
                get: { chapterTitlePendingIconChange != nil },
                set: { if !$0 { chapterTitlePendingIconChange = nil } }
            )) {
                if let title = chapterTitlePendingIconChange {
                    SectionIconPickerView(currentAssetName: chapterIcons[title]) { assetName in
                        chapterIcons[title] = assetName
                    }
                }
            }
        }
    }

    private func chapterOrderRow(_ title: String) -> some View {
        HStack(spacing: 12) {
            chapterIconThumbnail(for: title)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Button("Change") {
                    chapterTitlePendingIconChange = title
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func chapterIconThumbnail(for title: String) -> some View {
        if let assetName = chapterIcons[title], let icon = CookbookSectionIconCatalog.icon(named: assetName) {
            Image(icon.assetName)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(width: 60, height: 60)
                .background(Color(white: 0.95))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 60, height: 60)
                .overlay {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var colorSwatchGrid: some View {
        HStack(spacing: 12) {
            ForEach(Self.curatedColorHexes, id: \.self) { hex in
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
            } else {
                Label("Add Cover Image", systemImage: "photo")
            }
        }
        .accessibilityLabel(coverImageData == nil ? "Add cover image" : "Change cover image")
        .disabled(coverImageRequiresAnnualProMembership)
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    coverImageData = data
                    removesExistingCoverImage = false
                }
            }
        }

        if coverImageData != nil {
            Button("Remove Cover Image", role: .destructive) {
                coverImageData = nil
                selectedPhotoItem = nil
                removesExistingCoverImage = true
            }
        }
    }
    #endif

    private func catalogBinding(for title: String) -> Binding<Bool> {
        Binding(
            get: { chapterTitles.contains(title) },
            set: { isSelected in
                if isSelected {
                    addChapter(title)
                } else {
                    chapterTitles.removeAll { $0 == title }
                }
            }
        )
    }

    private func addCustomSection() {
        let trimmed = newCustomSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chapterTitles.contains(trimmed) else { return }
        addChapter(trimmed)
        newCustomSectionTitle = ""
    }

    /// Shared by both add paths (catalog toggle-on and custom-name Add) so
    /// every new chapter gets the same default-icon treatment — a custom
    /// name that happens to match a manifest category (e.g. typed in a
    /// different case) still gets its icon, not just ones picked from the
    /// catalog list.
    private func addChapter(_ title: String) {
        guard !chapterTitles.contains(title) else { return }
        chapterTitles.append(title)
        if chapterIcons[title] == nil, let defaultIcon = CookbookSectionIconCatalog.defaultIcon(forChapterTitled: title) {
            chapterIcons[title] = defaultIcon.assetName
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    /// `@Query` isn't readable inside `init(mode:)` — the modelContext
    /// environment value isn't wired up until the view is actually
    /// installed — so the untouched "My Cookbook" default set there gets
    /// corrected here instead, the moment the view first appears (well
    /// before the user could plausibly have typed anything). Guarded on
    /// `.create` and the title still being the untouched default, so this
    /// never touches `.edit` mode or a title the user already changed.
    /// Live `isCloudSynced` (the toggle's current value, not the value at
    /// open time) — flipping Sync to Cloud on immediately requires Annual
    /// Pro Membership for a cover image, even before Done is tapped.
    private var coverImageRequiresAnnualProMembership: Bool {
        isCloudSynced && entitlement?.isActiveAnnualProMember != true
    }

    private func loadEntitlement() async {
        guard let userID = accountState.currentUserID else {
            entitlement = nil
            return
        }
        entitlement = try? await entitlementService.fetchEntitlement(userID: userID)
    }

    private func clearDefaultTitleIfAlreadyTaken() {
        guard case .create(let ownerID) = mode, title == "My Cookbook" else { return }
        let alreadyHasDefaultNamed = allCookbooks.contains { $0.ownerID == ownerID && $0.title == "My Cookbook" }
        guard alreadyHasDefaultNamed else { return }
        title = ""
        titleWasClearedDueToCollision = true
    }

    /// Saves locally, then — only if Sync to Cloud was just switched on
    /// this session — pushes immediately. Dismisses on success either way;
    /// a push failure shows an alert instead (whose own dismiss button
    /// closes this screen), since the local save already succeeded and
    /// isn't itself in question.
    private func saveAndSync() async {
        guard let cookbook = save() else { return }
        guard !initialIsCloudSynced, isCloudSynced else {
            dismiss()
            return
        }
        guard let ownerUserID = accountState.currentUserID else {
            dismiss()
            return
        }

        isSyncing = true
        defer { isSyncing = false }
        do {
            let cookbookID = cookbook.id
            let recipeDescriptor = FetchDescriptor<Recipe>(predicate: #Predicate<Recipe> { $0.cookbookID == cookbookID })
            let recipes = try modelContext.fetch(recipeDescriptor)
            let entitlement = try? await entitlementService.fetchEntitlement(userID: ownerUserID)
            try await PersonalCookbookSyncCoordinator.push(
                cookbook, recipes: recipes, ownerUserID: ownerUserID,
                syncService: syncService, photoUploadService: photoUploadService,
                isActiveProMember: entitlement?.isActiveAnnualProMember == true
            )
            try? modelContext.save()
            dismiss()
        } catch {
            syncErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    private func save() -> Cookbook? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Give your cookbook a title."
            return nil
        }
        validationMessage = nil

        let cookbook: Cookbook
        switch mode {
        case .create(let ownerID):
            cookbook = Cookbook(ownerID: ownerID, title: trimmedTitle, coverColorHex: coverColorHex)
            modelContext.insert(cookbook)
            // Brand new, so it can't hold any pre-migration ingredient
            // text — see CookbookMigrator's matching comment.
            RecipeStandardizationState.markStandardized(cookbook.id)
        case .edit(let existing):
            cookbook = existing
            cookbook.title = trimmedTitle
            cookbook.coverColorHex = coverColorHex
        }

        cookbook.hasBeenConfigured = true
        cookbook.chaptersManuallyReordered = chaptersManuallyReordered
        cookbook.coverStyleImageName = coverStyleImageName
        cookbook.isCloudSynced = isCloudSynced
        cookbook.updatedAt = .now

        #if os(iOS)
        if removesExistingCoverImage, let existingFilename = cookbook.coverImageFilename {
            PhotoStore.delete(existingFilename)
            cookbook.coverImageFilename = nil
        }
        if let coverImageData {
            if let existingFilename = cookbook.coverImageFilename {
                PhotoStore.delete(existingFilename)
            }
            cookbook.coverImageFilename = try? PhotoStore.save(coverImageData)
        }
        #endif

        // Display/save order is exactly chapterTitles' order — the user's
        // own drag-to-reorder, not a fixed catalog-then-custom order.
        //
        // Chapters that are kept reuse their existing CookbookSection
        // instance (and therefore its id) rather than being recreated —
        // Recipe.sectionID is a plain scalar UUID copy, not a live
        // relationship, so a fresh id on every edit was silently unfiling
        // every recipe in the cookbook (RecipeListView.groupedBySection
        // buckets any sectionID it doesn't recognize into "Other"), even
        // when the edit didn't touch chapters at all.
        var existingSectionsByTitle: [String: CookbookSection] = [:]
        for section in cookbook.sections {
            existingSectionsByTitle[section.title] = section
        }

        var sections: [CookbookSection] = []
        for (index, title) in chapterTitles.enumerated() {
            let section = existingSectionsByTitle[title] ?? CookbookSection(title: title, sortOrder: index)
            section.sortOrder = index
            section.iconAssetName = chapterIcons[title]
            sections.append(section)
        }
        let keptTitles = Set(chapterTitles)
        for section in cookbook.sections where !keptTitles.contains(section.title) {
            modelContext.delete(section)
        }
        cookbook.sections = sections

        do {
            try modelContext.save()
            return cookbook
        } catch {
            validationMessage = "Couldn't save this cookbook: \(error.localizedDescription)"
            return nil
        }
    }
}

#Preview {
    CookbookConfigurationView(mode: .create(ownerID: "preview-owner"))
        .modelContainer(for: Cookbook.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
}
