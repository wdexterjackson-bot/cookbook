//
//  CreateEditRecipeView.swift
//  cookbook
//
//  Milestone 5C rework: a flowing List(.plain) page (not a boxed Form),
//  with structured per-row ingredient/step editors (name, then amount,
//  then a selectable-but-optional unit) instead of a free-text multi-line
//  blob. Reorder handles come from SwiftUI's native List editing affordances,
//  scoped to just the ingredient/step rows via a local `.editMode` override
//  — the rest of the page (title, photo, tags, notes) stays in normal mode.
//
//  Simplification, stated plainly rather than hidden: earlier versions
//  supported multiple headed ingredient/step sub-sections per recipe; this
//  editor flattens everything into one ingredient list and one step list
//  (matching the reference layout the user asked to follow, which shows no
//  sub-headings). Editing a recipe that already has multiple sections
//  merges them into one on save — no data is dropped, just the grouping.
//

import SwiftUI
import SwiftData
import PhotosUI
#if os(iOS)
import UIKit
#endif

/// A raised, physically-pushable look — filled and shadowed at rest,
/// flattens and shifts down while pressed. Used for "Paste Recipe" so its
/// active/inactive state (something to paste vs. nothing) reads instantly
/// from color alone, on top of the tap disabling itself.
private struct PushableButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? Color.accentColor : Color.secondary.opacity(0.15))
            )
            .shadow(
                color: isEnabled ? Color.accentColor.opacity(0.45) : .clear,
                radius: configuration.isPressed ? 0 : 4,
                y: configuration.isPressed ? 0 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

private struct DraftIngredientRow: Identifiable {
    let id = UUID()
    var name: String = ""
    var quantityText: String = ""
    var unit: String = ""
    var isOptional: Bool = false

    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && quantityText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct DraftStepRow: Identifiable {
    let id = UUID()
    var text: String = ""
}

struct CreateEditRecipeView: View {
    enum Mode {
        case create
        case edit(Recipe)
        /// Review-before-import (REC-008): pre-fills the same editor as
        /// `.create` from a search result, but save() also stamps
        /// nutrition/diet/external-source fields the plain create flow
        /// never touches.
        case importing(DiscoveredRecipe)
    }

    static let commonUnits = [
        "cup", "tbsp", "tsp", "oz", "fl oz", "lb", "g", "kg", "ml", "L",
        "pinch", "clove", "slice", "can", "package", "whole",
    ]

    let mode: Mode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query private var allCookbooks: [Cookbook]

    @State private var title: String
    @State private var summary: String
    @State private var yield: String
    @State private var notes: String
    @State private var ingredientRows: [DraftIngredientRow]
    @State private var stepRows: [DraftStepRow]
    @State private var selectedChapterID: UUID?
    @State private var tags: [String]
    @State private var newTagText = ""
    @State private var validationMessage: String?

    @State private var importText = ""
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var hasClipboardText = false
    @Environment(\.scenePhase) private var scenePhase
    private let lineImportService: RecipeLineImportServicing = FoundationModelsLineImportService()

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var heroImageData: Data?
    @State private var removesExistingPhoto = false

    @FocusState private var focusedIngredientRowID: UUID?
    @FocusState private var focusedStepRowID: UUID?

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _summary = State(initialValue: "")
            _yield = State(initialValue: "")
            _notes = State(initialValue: "")
            _ingredientRows = State(initialValue: [DraftIngredientRow()])
            _stepRows = State(initialValue: [DraftStepRow()])
            _selectedChapterID = State(initialValue: nil)
            _tags = State(initialValue: [])
            _heroImageData = State(initialValue: nil)

        case .edit(let recipe):
            _title = State(initialValue: recipe.title)
            _summary = State(initialValue: recipe.summary)
            _yield = State(initialValue: recipe.yield)
            _notes = State(initialValue: recipe.notes)
            _selectedChapterID = State(initialValue: recipe.sectionID)
            _tags = State(initialValue: recipe.tags)

            let ingredientDrafts = Self.makeIngredientDrafts(from: recipe)
            _ingredientRows = State(initialValue: ingredientDrafts.isEmpty ? [DraftIngredientRow()] : ingredientDrafts)

            let stepDrafts = Self.makeStepDrafts(from: recipe)
            _stepRows = State(initialValue: stepDrafts.isEmpty ? [DraftStepRow()] : stepDrafts)

            if let filename = recipe.heroPhotoFilename {
                _heroImageData = State(initialValue: PhotoStore.data(for: filename))
            } else {
                _heroImageData = State(initialValue: nil)
            }

        case .importing(let discovered):
            _title = State(initialValue: discovered.title)
            _summary = State(initialValue: discovered.summary ?? "")
            _yield = State(initialValue: discovered.servings.map { "Serves \($0)" } ?? "")
            _notes = State(initialValue: "")
            _selectedChapterID = State(initialValue: nil)
            _tags = State(initialValue: [])

            let ingredientDrafts = discovered.ingredients.map { DraftIngredientRow(name: $0.displayText) }
            _ingredientRows = State(initialValue: ingredientDrafts.isEmpty ? [DraftIngredientRow()] : ingredientDrafts)

            let stepDrafts = discovered.steps.map { DraftStepRow(text: $0) }
            _stepRows = State(initialValue: stepDrafts.isEmpty ? [DraftStepRow()] : stepDrafts)

            _heroImageData = State(initialValue: nil)
        }
    }

    private static func makeIngredientDrafts(from recipe: Recipe) -> [DraftIngredientRow] {
        let sortedSections = recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
        return sortedSections.flatMap { section in
            section.ingredients.sorted { $0.sortOrder < $1.sortOrder }
        }.map { ingredient in
            DraftIngredientRow(
                name: ingredient.name,
                quantityText: ingredient.quantityValue.map(Self.formatQuantity) ?? "",
                unit: ingredient.unit ?? "",
                isOptional: ingredient.isOptional
            )
        }
    }

    private static func makeStepDrafts(from recipe: Recipe) -> [DraftStepRow] {
        let sortedSections = recipe.stepSections.sorted { $0.sortOrder < $1.sortOrder }
        return sortedSections.flatMap { section in
            section.steps.sorted { $0.sortOrder < $1.sortOrder }
        }.map { DraftStepRow(text: $0.text) }
    }

    private static func formatQuantity(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Recipe") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                    TextField("Yield (e.g. Serves 6)", text: $yield)
                }

                if let chapters = activeCookbook?.sections, !chapters.isEmpty {
                    Section("Chapter") {
                        Picker("Chapter", selection: $selectedChapterID) {
                            Text("None").tag(UUID?.none)
                            ForEach(chapters.sorted { $0.sortOrder < $1.sortOrder }) { chapter in
                                Text(chapter.title).tag(UUID?.some(chapter.id))
                            }
                        }
                    }
                }

                #if os(iOS)
                Section("Photo") {
                    photoPicker
                }
                #endif

                ingredientsSection
                stepsSection
                importSection
                tagsSection

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach($ingredientRows) { $row in
                ingredientRow($row)
            }
            .onDelete { offsets in
                ingredientRows.remove(atOffsets: offsets)
            }
            .onMove { from, to in
                ingredientRows.move(fromOffsets: from, toOffset: to)
            }
            .environment(\.editMode, .constant(.active))

            addRowButton(label: "Add an ingredient") {
                let row = DraftIngredientRow()
                ingredientRows.append(row)
                focusedIngredientRowID = row.id
            }
        }
    }

    private func ingredientRow(_ row: Binding<DraftIngredientRow>) -> some View {
        HStack(spacing: 8) {
            removeRowButton(accessibilityLabel: "Remove ingredient") {
                ingredientRows.removeAll { $0.id == row.wrappedValue.id }
            }

            TextField("Ingredient", text: row.name)
                .focused($focusedIngredientRowID, equals: row.wrappedValue.id)
                .accessibilityLabel("Ingredient name")

            TextField("Amount", text: row.quantityText)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .accessibilityLabel("Amount")

            HStack(spacing: 2) {
                TextField("unit", text: row.unit)
                    .frame(width: 56)
                    .accessibilityLabel("Unit")
                Menu {
                    ForEach(Self.commonUnits, id: \.self) { unit in
                        Button(unit) { row.wrappedValue.unit = unit }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Choose a unit")
            }
        }
        .padding(.vertical, 2)
    }

    /// Styled to read as part of the list itself — a green "+" circle
    /// matching the size/weight of the system red delete circle edit mode
    /// already renders on every row above it — rather than a separate
    /// button hanging off the bottom of the section.
    private func addRowButton(label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text(label)
                    .foregroundStyle(.secondary)
                    .italic()
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
    }

    /// Explicit, always-visible per-row delete — doesn't depend on List's
    /// native swipe/edit-mode delete chrome, which wasn't reliably
    /// reachable in practice inside this flat List(.plain) layout.
    private func removeRowButton(accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section("Steps") {
            ForEach($stepRows) { $row in
                HStack(spacing: 8) {
                    removeRowButton(accessibilityLabel: "Remove step") {
                        stepRows.removeAll { $0.id == row.id }
                    }

                    TextField("Step", text: $row.text, axis: .vertical)
                        .focused($focusedStepRowID, equals: row.id)
                        .accessibilityLabel("Step")
                }
                .padding(.vertical, 2)
            }
            .onDelete { offsets in
                stepRows.remove(atOffsets: offsets)
            }
            .onMove { from, to in
                stepRows.move(fromOffsets: from, toOffset: to)
            }
            .environment(\.editMode, .constant(.active))

            addRowButton(label: "Add a step") {
                let row = DraftStepRow()
                stepRows.append(row)
                focusedStepRowID = row.id
            }
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            if lineImportService.isAvailable {
                #if os(iOS)
                HStack {
                    Spacer()
                    Button("Paste Recipe") {
                        pasteFromClipboard()
                    }
                    .buttonStyle(PushableButtonStyle())
                    .disabled(!hasClipboardText)
                }
                #endif

                // Placeholder sits BEHIND the TextEditor (not overlaid on
                // top of it) — an overlay in front of TextEditor's
                // UITextView was interfering with its own long-press
                // paste/selection gestures. scrollContentBackground(.hidden)
                // is what lets the placeholder show through when empty.
                ZStack(alignment: .topLeading) {
                    if importText.isEmpty {
                        Text("Tap here to paste or type ingredients and steps…")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $importText)
                        .frame(minHeight: 120)
                        .padding(6)
                        #if os(iOS)
                        .scrollContentBackground(.hidden)
                        #endif
                        .accessibilityLabel("Paste ingredients and steps to import")
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                Button {
                    Task { await performImport() }
                } label: {
                    if isImporting {
                        ProgressView()
                    } else {
                        Label("Import", systemImage: "sparkles")
                    }
                }
                .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)

                if let importErrorMessage {
                    Text(importErrorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } else {
                Text("On-device AI import needs Apple Intelligence enabled on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Import")
        } footer: {
            Text("Paste a full list of ingredients and steps — AI will sort them into Ingredients and Steps above.")
        }
        #if os(iOS)
        .onAppear {
            refreshClipboardStatus()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refreshClipboardStatus()
            }
        }
        #endif
    }

    #if os(iOS)
    private func refreshClipboardStatus() {
        hasClipboardText = UIPasteboard.general.hasStrings
    }

    private func pasteFromClipboard() {
        guard let text = UIPasteboard.general.string else { return }
        importText = text
    }
    #endif

    private func performImport() async {
        isImporting = true
        importErrorMessage = nil
        defer { isImporting = false }
        do {
            let result = try await lineImportService.parseLines(from: importText)

            ingredientRows.removeAll { $0.isBlank }
            for parsed in result.ingredients {
                ingredientRows.append(DraftIngredientRow(
                    name: parsed.name,
                    quantityText: parsed.quantity.map(Self.formatQuantity) ?? "",
                    unit: parsed.unit ?? ""
                ))
            }
            if ingredientRows.isEmpty {
                ingredientRows = [DraftIngredientRow()]
            }

            stepRows.removeAll { $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            for stepText in result.steps {
                stepRows.append(DraftStepRow(text: stepText))
            }
            if stepRows.isEmpty {
                stepRows = [DraftStepRow()]
            }

            importText = ""
        } catch {
            importErrorMessage = "Couldn't import — try again, or add these manually below."
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        Section("Tags") {
            if !tags.isEmpty {
                tagChipsRow(tags, style: .selected) { tag in
                    tags.removeAll { $0 == tag }
                }
            }

            let suggestions = TagCatalog.suggestedTags.filter { !tags.contains($0) }
            if !suggestions.isEmpty {
                tagChipsRow(suggestions, style: .suggestion) { tag in
                    tags.append(tag)
                }
            }

            HStack {
                TextField("Custom tag", text: $newTagText)
                    .onSubmit(addCustomTag)
                Button("Add", action: addCustomTag)
                    .disabled(newTagText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private enum TagChipStyle {
        case selected
        case suggestion
    }

    private func tagChipsRow(_ chipTags: [String], style: TagChipStyle, onTap: @escaping (String) -> Void) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chipTags, id: \.self) { tag in
                    Button {
                        onTap(tag)
                    } label: {
                        HStack(spacing: 4) {
                            Text(tag)
                            Image(systemName: style == .selected ? "xmark.circle.fill" : "plus.circle")
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(style == .selected ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.12)))
                        .foregroundStyle(style == .selected ? Color.accentColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(style == .selected ? "Remove tag \(tag)" : "Add tag \(tag)")
                }
            }
        }
    }

    private func addCustomTag() {
        let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTagText = ""
    }

    #if os(iOS)
    @ViewBuilder
    private var photoPicker: some View {
        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
            if let heroImageData, let uiImage = UIImage(data: heroImageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                Label("Add Photo", systemImage: "photo")
            }
        }
        .accessibilityLabel(heroImageData == nil ? "Add photo" : "Change photo")
        .onChange(of: selectedPhotoItem) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    heroImageData = data
                    removesExistingPhoto = false
                }
            }
        }

        if heroImageData != nil {
            Button("Remove Photo", role: .destructive) {
                heroImageData = nil
                selectedPhotoItem = nil
                removesExistingPhoto = true
            }
        }
    }
    #endif

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Recipe"
        case .edit: return "Edit Recipe"
        case .importing: return "Review & Add Recipe"
        }
    }

    private var activeCookbook: Cookbook? {
        allCookbooks.first { $0.id == activeCookbookState.activeCookbookID }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasIngredientContent = ingredientRows.contains { !$0.isBlank }
        let hasStepContent = stepRows.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard !trimmedTitle.isEmpty else {
            validationMessage = "Give your recipe a title."
            return
        }
        guard hasIngredientContent || hasStepContent else {
            validationMessage = "Add at least one ingredient or instruction."
            return
        }
        validationMessage = nil

        let recipe: Recipe
        switch mode {
        case .create:
            recipe = Recipe(ownerID: accountState.currentOwnerID, title: trimmedTitle, sourceType: .manual)
            recipe.cookbookID = activeCookbookState.activeCookbookID
            modelContext.insert(recipe)
        case .edit(let existing):
            recipe = existing
            recipe.title = trimmedTitle
            for section in recipe.ingredientSections {
                modelContext.delete(section)
            }
            for section in recipe.stepSections {
                modelContext.delete(section)
            }
        case .importing(let discovered):
            recipe = Recipe(ownerID: accountState.currentOwnerID, title: trimmedTitle, sourceType: .webImport)
            recipe.cookbookID = activeCookbookState.activeCookbookID
            recipe.sourceURL = discovered.sourceURL
            recipe.sourceAuthorText = discovered.attributionText
            recipe.externalSource = discovered.source.rawValue
            recipe.externalSourceID = discovered.externalID
            recipe.totalTimeMinutes = discovered.readyInMinutes
            recipe.dietaryLabels = discovered.dietFlags
            if let nutrition = discovered.nutrition {
                recipe.calories = nutrition.calories
                recipe.proteinGrams = nutrition.proteinGrams
                recipe.fatGrams = nutrition.fatGrams
                recipe.carbsGrams = nutrition.carbsGrams
                recipe.sugarGrams = nutrition.sugarGrams
                recipe.fiberGrams = nutrition.fiberGrams
                recipe.sodiumMilligrams = nutrition.sodiumMilligrams
            }
            modelContext.insert(recipe)
        }

        recipe.summary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.yield = yield.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.sectionID = selectedChapterID
        recipe.tags = tags
        recipe.updatedAt = .now

        if let ingredientSection = Self.buildIngredientSection(from: ingredientRows) {
            recipe.ingredientSections = [ingredientSection]
        } else {
            recipe.ingredientSections = []
        }
        if let stepSection = Self.buildStepSection(from: stepRows) {
            recipe.stepSections = [stepSection]
        } else {
            recipe.stepSections = []
        }

        #if os(iOS)
        applyPhotoChanges(to: recipe)
        #endif

        try? modelContext.save()
        dismiss()
    }

    #if os(iOS)
    private func applyPhotoChanges(to recipe: Recipe) {
        if removesExistingPhoto, let existingFilename = recipe.heroPhotoFilename {
            PhotoStore.delete(existingFilename)
            recipe.heroPhotoFilename = nil
        }
        if let heroImageData {
            if let existingFilename = recipe.heroPhotoFilename {
                PhotoStore.delete(existingFilename)
            }
            recipe.heroPhotoFilename = try? PhotoStore.save(heroImageData)
        }
    }
    #endif

    private static func buildIngredientSection(from rows: [DraftIngredientRow]) -> IngredientSection? {
        let nonBlankRows = rows.filter { !$0.isBlank }
        guard !nonBlankRows.isEmpty else { return nil }

        let section = IngredientSection(heading: nil, sortOrder: 0)
        section.ingredients = nonBlankRows.enumerated().map { index, row in
            let trimmedName = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedQuantityText = row.quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedUnit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)
            let parsedQuantity = Double(trimmedQuantityText)

            return Ingredient(
                displayText: Self.composeDisplayText(name: trimmedName, quantityText: trimmedQuantityText, unit: trimmedUnit),
                name: trimmedName.isEmpty ? trimmedQuantityText : trimmedName,
                quantityValue: parsedQuantity,
                unit: trimmedUnit.isEmpty ? nil : trimmedUnit,
                preparationNote: nil,
                isOptional: row.isOptional,
                sortOrder: index
            )
        }
        return section
    }

    /// Preserves the raw typed amount even when it doesn't parse as a
    /// Double (e.g. "1/2" or "to taste") — REC-004: retain the
    /// author-entered string for fidelity even when normalized values
    /// can't be derived from it.
    private static func composeDisplayText(name: String, quantityText: String, unit: String) -> String {
        var parts: [String] = []
        if !quantityText.isEmpty { parts.append(quantityText) }
        if !unit.isEmpty { parts.append(unit) }
        if !name.isEmpty { parts.append(name) }
        return parts.isEmpty ? name : parts.joined(separator: " ")
    }

    private static func buildStepSection(from rows: [DraftStepRow]) -> StepSection? {
        let nonBlankRows = rows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !nonBlankRows.isEmpty else { return nil }

        let section = StepSection(heading: nil, sortOrder: 0)
        section.steps = nonBlankRows.enumerated().map { index, row in
            Step(text: row.text.trimmingCharacters(in: .whitespacesAndNewlines), sortOrder: index)
        }
        return section
    }
}

#Preview {
    CreateEditRecipeView(mode: .create)
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
