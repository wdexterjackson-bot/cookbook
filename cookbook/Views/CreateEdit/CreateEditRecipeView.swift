//
//  CreateEditRecipeView.swift
//  cookbook
//

import SwiftUI
import SwiftData
import PhotosUI

/// A section's raw editable state before it's turned into IngredientSection/
/// StepSection model objects on save. Ingredient/step rows are entered as
/// one-per-line free text (supporting paste-multiline per REC-005); each
/// non-empty line becomes a row's displayText verbatim. This is a Phase 1
/// simplification — no quantity/unit parsing yet (REC-004's normalized
/// fields stay nil), only the author's raw text is preserved.
private struct DraftSection: Identifiable {
    let id = UUID()
    var heading: String = ""
    var linesText: String = ""
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
    @State private var ingredientSections: [DraftSection]
    @State private var stepSections: [DraftSection]
    @State private var selectedChapterID: UUID?
    @State private var validationMessage: String?

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var heroImageData: Data?
    @State private var removesExistingPhoto = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _summary = State(initialValue: "")
            _yield = State(initialValue: "")
            _notes = State(initialValue: "")
            _ingredientSections = State(initialValue: [DraftSection()])
            _stepSections = State(initialValue: [DraftSection()])
            _selectedChapterID = State(initialValue: nil)
            _heroImageData = State(initialValue: nil)

        case .edit(let recipe):
            _title = State(initialValue: recipe.title)
            _summary = State(initialValue: recipe.summary)
            _yield = State(initialValue: recipe.yield)
            _notes = State(initialValue: recipe.notes)

            let sortedIngredientSections = recipe.ingredientSections.sorted { $0.sortOrder < $1.sortOrder }
            let ingredientDrafts = sortedIngredientSections.map(Self.makeIngredientDraft)
            _ingredientSections = State(initialValue: ingredientDrafts.isEmpty ? [DraftSection()] : ingredientDrafts)

            let sortedStepSections = recipe.stepSections.sorted { $0.sortOrder < $1.sortOrder }
            let stepDrafts = sortedStepSections.map(Self.makeStepDraft)
            _stepSections = State(initialValue: stepDrafts.isEmpty ? [DraftSection()] : stepDrafts)
            _selectedChapterID = State(initialValue: recipe.sectionID)

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

            let ingredientDraft = DraftSection(
                heading: "",
                linesText: discovered.ingredients.map(\.displayText).joined(separator: "\n")
            )
            _ingredientSections = State(initialValue: [ingredientDraft])

            let stepDraft = DraftSection(heading: "", linesText: discovered.steps.joined(separator: "\n"))
            _stepSections = State(initialValue: [stepDraft])
            _selectedChapterID = State(initialValue: nil)
            _heroImageData = State(initialValue: nil)
        }
    }

    private static func makeIngredientDraft(from section: IngredientSection) -> DraftSection {
        let sortedIngredients = section.ingredients.sorted { $0.sortOrder < $1.sortOrder }
        let lines = sortedIngredients.map { $0.displayText }
        return DraftSection(heading: section.heading ?? "", linesText: lines.joined(separator: "\n"))
    }

    private static func makeStepDraft(from section: StepSection) -> DraftSection {
        let sortedSteps = section.steps.sorted { $0.sortOrder < $1.sortOrder }
        let lines = sortedSteps.map { $0.text }
        return DraftSection(heading: section.heading ?? "", linesText: lines.joined(separator: "\n"))
    }

    var body: some View {
        NavigationStack {
            Form {
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

                ingredientSectionsEditor
                stepSectionsEditor

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

    private var ingredientSectionsEditor: some View {
        ForEach($ingredientSections) { $section in
            Section {
                TextField("Section heading (optional)", text: $section.heading)
                TextEditor(text: $section.linesText)
                    .frame(minHeight: 100)
                    .accessibilityLabel("Ingredients, one per line")
            } header: {
                sectionHeader("Ingredients", canRemove: ingredientSections.count > 1) {
                    ingredientSections.removeAll { $0.id == section.id }
                }
            }
        }
    }

    private var stepSectionsEditor: some View {
        Group {
            ForEach($stepSections) { $section in
                Section {
                    TextField("Section heading (optional)", text: $section.heading)
                    TextEditor(text: $section.linesText)
                        .frame(minHeight: 100)
                        .accessibilityLabel("Steps, one per line")
                } header: {
                    sectionHeader("Steps", canRemove: stepSections.count > 1) {
                        stepSections.removeAll { $0.id == section.id }
                    }
                }
            }

            Section {
                Button {
                    ingredientSections.append(DraftSection())
                } label: {
                    Label("Add Ingredient Section", systemImage: "plus")
                }
                Button {
                    stepSections.append(DraftSection())
                } label: {
                    Label("Add Step Section", systemImage: "plus")
                }
            }
        }
    }

    private func sectionHeader(_ title: String, canRemove: Bool, onRemove: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Spacer()
            if canRemove {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("Remove \(title.lowercased()) section")
            }
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var activeCookbook: Cookbook? {
        allCookbooks.first { $0.id == activeCookbookState.activeCookbookID }
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Recipe"
        case .edit: return "Edit Recipe"
        case .importing: return "Review & Add Recipe"
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasIngredientContent = ingredientSections.contains {
            !$0.linesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let hasStepContent = stepSections.contains {
            !$0.linesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

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
        recipe.updatedAt = .now

        recipe.ingredientSections = ingredientSections.enumerated().compactMap { index, draft in
            buildIngredientSection(from: draft, sortOrder: index)
        }
        recipe.stepSections = stepSections.enumerated().compactMap { index, draft in
            buildStepSection(from: draft, sortOrder: index)
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

    private func buildIngredientSection(from draft: DraftSection, sortOrder: Int) -> IngredientSection? {
        let lines = draft.linesText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedHeading = draft.heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lines.isEmpty || !trimmedHeading.isEmpty else { return nil }

        let section = IngredientSection(heading: trimmedHeading.isEmpty ? nil : trimmedHeading, sortOrder: sortOrder)
        section.ingredients = lines.enumerated().map { index, line in
            Ingredient(displayText: line, name: line, sortOrder: index)
        }
        return section
    }

    private func buildStepSection(from draft: DraftSection, sortOrder: Int) -> StepSection? {
        let lines = draft.linesText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let trimmedHeading = draft.heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lines.isEmpty || !trimmedHeading.isEmpty else { return nil }

        let section = StepSection(heading: trimmedHeading.isEmpty ? nil : trimmedHeading, sortOrder: sortOrder)
        section.steps = lines.enumerated().map { index, line in
            Step(text: line, sortOrder: index)
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
