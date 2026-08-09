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
import PhotosUI

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

    private let syncService: PersonalCookbookSyncServicing = FirestorePersonalCookbookSyncService()
    private let photoUploadService: PersonalCookbookPhotoUploadServicing = FirebasePersonalCookbookPhotoUploadService()

    @State private var title: String
    @State private var coverColorHex: String
    /// Priority for the cover actually shown is coverImageFilename >
    /// coverStyleImageName > coverColorHex — a custom photo always wins,
    /// a chosen style beats plain color, color is the universal fallback.
    @State private var coverStyleImageName: String?
    @State private var coverImageData: Data?
    @State private var removesExistingCoverImage = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    /// One ordered list for every chapter currently included — whether it
    /// came from a catalog toggle or the custom-name field — so the two
    /// can be freely reordered together instead of always showing catalog
    /// chapters first. Display/save order is exactly this array's order.
    @State private var chapterTitles: [String]
    /// Flips to true the moment the user actually drags to reorder (not
    /// from adding/removing a chapter) — see Cookbook.chaptersManuallyReordered.
    @State private var chaptersManuallyReordered: Bool
    @State private var newCustomSectionTitle = ""
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

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "My Cookbook")
            _coverColorHex = State(initialValue: Cookbook.defaultColorHex)
            _coverStyleImageName = State(initialValue: nil)
            _coverImageData = State(initialValue: nil)
            _chapterTitles = State(initialValue: [])
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
            _chaptersManuallyReordered = State(initialValue: cookbook.chaptersManuallyReordered)
            _isCloudSynced = State(initialValue: cookbook.isCloudSynced)
            initialIsCloudSynced = cookbook.isCloudSynced
            _lastSyncedAt = State(initialValue: cookbook.lastSyncedAt)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Cookbook Title", text: $title)
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
                Section("Cover Image") {
                    coverImagePicker
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
                        Text(title)
                    }
                    .onDelete { offsets in
                        chapterTitles.remove(atOffsets: offsets)
                    }
                    .onMove { from, to in
                        chapterTitles.move(fromOffsets: from, toOffset: to)
                        chaptersManuallyReordered = true
                    }
                    .environment(\.editMode, .constant(.active))

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
            .scrollContentBackground(.hidden)
            .background(Color.potluckCream)
            .navigationTitle(isEditing ? "Edit Cookbook" : "New Cookbook")
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
                    if !chapterTitles.contains(title) {
                        chapterTitles.append(title)
                    }
                } else {
                    chapterTitles.removeAll { $0 == title }
                }
            }
        )
    }

    private func addCustomSection() {
        let trimmed = newCustomSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chapterTitles.contains(trimmed) else { return }
        chapterTitles.append(trimmed)
        newCustomSectionTitle = ""
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
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
            try await PersonalCookbookSyncCoordinator.push(
                cookbook, recipes: recipes, ownerUserID: ownerUserID,
                syncService: syncService, photoUploadService: photoUploadService
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
