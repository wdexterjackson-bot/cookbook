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

    @State private var title: String
    @State private var coverColorHex: String
    @State private var coverImageData: Data?
    @State private var removesExistingCoverImage = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedCatalogTitles: Set<String>
    @State private var customSectionTitles: [String]
    @State private var newCustomSectionTitle = ""
    @State private var validationMessage: String?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "My Cookbook")
            _coverColorHex = State(initialValue: Cookbook.defaultColorHex)
            _coverImageData = State(initialValue: nil)
            _selectedCatalogTitles = State(initialValue: [])
            _customSectionTitles = State(initialValue: [])

        case .edit(let cookbook):
            _title = State(initialValue: cookbook.title)
            _coverColorHex = State(initialValue: cookbook.coverColorHex)
            if let filename = cookbook.coverImageFilename {
                _coverImageData = State(initialValue: PhotoStore.data(for: filename))
            } else {
                _coverImageData = State(initialValue: nil)
            }

            let sortedSections = cookbook.sections.sorted { $0.sortOrder < $1.sortOrder }
            let catalogSet = Set(RecipeSectionCatalog.defaultChapterTitles)
            _selectedCatalogTitles = State(initialValue: Set(sortedSections.map(\.title).filter(catalogSet.contains)))
            _customSectionTitles = State(initialValue: sortedSections.map(\.title).filter { !catalogSet.contains($0) })
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Cookbook Title", text: $title)
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

                Section("Custom Chapters") {
                    ForEach(customSectionTitles, id: \.self) { customTitle in
                        Text(customTitle)
                    }
                    .onDelete { offsets in
                        customSectionTitles.remove(atOffsets: offsets)
                    }

                    HStack {
                        TextField("Other (custom chapter name)", text: $newCustomSectionTitle)
                            .onSubmit(addCustomSection)
                        Button("Add", action: addCustomSection)
                            .disabled(newCustomSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
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
                    Button("Done", action: save)
                }
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
            get: { selectedCatalogTitles.contains(title) },
            set: { isSelected in
                if isSelected {
                    selectedCatalogTitles.insert(title)
                } else {
                    selectedCatalogTitles.remove(title)
                }
            }
        )
    }

    private func addCustomSection() {
        let trimmed = newCustomSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !customSectionTitles.contains(trimmed) else { return }
        customSectionTitles.append(trimmed)
        newCustomSectionTitle = ""
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            validationMessage = "Give your cookbook a title."
            return
        }
        validationMessage = nil

        let cookbook: Cookbook
        switch mode {
        case .create(let ownerID):
            cookbook = Cookbook(ownerID: ownerID, title: trimmedTitle, coverColorHex: coverColorHex)
            modelContext.insert(cookbook)
        case .edit(let existing):
            cookbook = existing
            cookbook.title = trimmedTitle
            cookbook.coverColorHex = coverColorHex
            for section in cookbook.sections {
                modelContext.delete(section)
            }
        }

        cookbook.hasBeenConfigured = true
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

        // Catalog chapters first (in catalog order), then custom ones in
        // the order they were added — a documented simplification, not a
        // full arbitrary-reorder (see CookbookConfigurationView init).
        var sortOrder = 0
        var sections: [CookbookSection] = []
        for catalogTitle in RecipeSectionCatalog.defaultChapterTitles where selectedCatalogTitles.contains(catalogTitle) {
            sections.append(CookbookSection(title: catalogTitle, sortOrder: sortOrder))
            sortOrder += 1
        }
        for customTitle in customSectionTitles {
            sections.append(CookbookSection(title: customTitle, sortOrder: sortOrder))
            sortOrder += 1
        }
        cookbook.sections = sections

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    CookbookConfigurationView(mode: .create(ownerID: "preview-owner"))
        .modelContainer(for: Cookbook.self, inMemory: true)
}
