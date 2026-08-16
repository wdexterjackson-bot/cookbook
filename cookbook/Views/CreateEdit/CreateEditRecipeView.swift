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
#if os(iOS)
import PhotosUI
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
    var quantity: WheelQuantity = .zero
    var unit: String = ""
    var isOptional: Bool = false

    var isBlank: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && quantity == .zero
    }
}

private struct DraftStepRow: Identifiable {
    let id = UUID()
    var text: String = ""
}

/// A wheel picker is far too tall to inline into a compact ingredient
/// row, so tapping the row's Amount button presents this instead — one
/// shared sheet for whichever row is currently being edited, rather than
/// building a picker per row.
private struct AmountWheelPickerSheet: View {
    @Binding var quantity: WheelQuantity
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text(quantity.displayText.isEmpty ? "No Amount" : quantity.displayText)
                    .font(.title2.weight(.semibold))
                    .padding(.top)
                QuantityWheelPicker(quantity: $quantity)
            }
            .navigationTitle("Amount")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.height(320)])
        // Without this, the wheel Picker's own drag gesture loses the
        // gesture-recognizer race to the sheet's swipe-to-dismiss handler
        // — for a short sheet like this one, that race goes to dismiss
        // almost every time, so a touch meant to scroll the wheel instead
        // closes the whole sheet before any scrolling registers. Done is
        // still a normal, explicit way to close it.
        .interactiveDismissDisabled()
        #endif
    }
}

/// Wraps just the id being edited so the Amount sheet can use `.sheet(item:)`,
/// owned by CreateEditRecipeView (not IngredientsListSection below) and
/// presented from its NavigationStack rather than from anything nested
/// inside the List. Both of those are load-bearing, confirmed by direct
/// reproduction — not just tidiness.
///
/// A `.sheet` attached to a Section *nested inside a List* (as this one
/// originally was) reproducibly flickered the sheet's content through 4
/// onAppear calls within ~30ms of presenting, then force-closed it about
/// a second later without Done ever being tapped — visible to a user as
/// "I tap Amount and the wheel picker instantly disappears." List's
/// internal row/section diffing apparently doesn't preserve presentation
/// state reliably for a `.sheet` attached several levels down inside it,
/// regardless of the presented content's own view identity or how the
/// presentation is driven. Isolated via a minimal reproduction outside
/// this file entirely: extracting this section into its own child View,
/// switching from `.sheet(isPresented:)` to `.sheet(item:)`, flattening
/// surrounding sheet nesting one level up, disabling interactive dismiss,
/// and deferring the presenting state change to the next run loop turn
/// all failed to fix it individually or in combination. What did fix it
/// was moving the `.sheet` modifier itself off of anything inside the
/// List, to a modifier on the List instead (a sibling, not a descendant)
/// — see where it's actually attached, further down.
private struct AmountEditingTarget: Identifiable, Equatable {
    let id: UUID
}

private struct IngredientsListSection: View {
    @Binding var ingredientRows: [DraftIngredientRow]
    @Binding var amountEditingTarget: AmountEditingTarget?
    @FocusState private var focusedIngredientRowID: UUID?

    var body: some View {
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

            CreateEditRecipeView.addRowButton(label: "Add an ingredient") {
                let row = DraftIngredientRow()
                ingredientRows.append(row)
                focusedIngredientRowID = row.id
            }
        }
    }

    /// Quantity + unit lead, ingredient name trails — matches the order
    /// every read-only rendering of an ingredient line already uses
    /// (`composeDisplayText`/`RecipeFileImportCoordinator.displayText(for:)`
    /// both put amount and unit first), so the editor no longer reads
    /// backwards relative to how the line actually displays everywhere
    /// else (2026-08-15 feedback).
    private func ingredientRow(_ row: Binding<DraftIngredientRow>) -> some View {
        HStack(spacing: 8) {
            CreateEditRecipeView.removeRowButton(accessibilityLabel: "Remove ingredient") {
                ingredientRows.removeAll { $0.id == row.wrappedValue.id }
            }

            Button {
                // Resigning focus and presenting the sheet in the same
                // transaction stacks two UIKit-transition-triggering state
                // changes (keyboard dismissal + sheet presentation) into
                // one update — the same shape that caused a real crash
                // for Create-tab + sheet in RootTabView (see its matching
                // comment). Clear focus synchronously, defer presenting
                // to the next run loop turn.
                focusedIngredientRowID = nil
                Task { @MainActor in
                    amountEditingTarget = AmountEditingTarget(id: row.wrappedValue.id)
                }
            } label: {
                Text(row.wrappedValue.quantity.displayText.isEmpty ? "Amount" : row.wrappedValue.quantity.displayText)
                    .foregroundStyle(row.wrappedValue.quantity.displayText.isEmpty ? .secondary : .primary)
                    .frame(width: 64, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Amount")
            .accessibilityValue(row.wrappedValue.quantity.displayText.isEmpty ? "None" : row.wrappedValue.quantity.displayText)

            HStack(spacing: 2) {
                TextField("unit", text: row.unit)
                    .frame(width: 56)
                    .accessibilityLabel("Unit")
                Menu {
                    ForEach(CreateEditRecipeView.commonUnits, id: \.self) { unit in
                        Button(unit) { row.wrappedValue.unit = unit }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Choose a unit")
            }

            TextField("Ingredient", text: row.name)
                .focused($focusedIngredientRowID, equals: row.wrappedValue.id)
                .accessibilityLabel("Ingredient name")
        }
        .padding(.vertical, 2)
    }
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

    /// The canonical unit vocabulary — every value IngredientLineParser's
    /// unitAliases table normalizes onto, so a recognized abbreviation
    /// (however it was spelled in a source file) always lands on
    /// something also offered here in the picker (2026-08-15 feedback).
    static let commonUnits = [
        "cup", "tbsp", "tsp", "oz", "fl oz", "lb", "g", "mg", "kg", "mL", "liter", "gal",
        "pinch", "dash", "drop", "handful",
        "clove", "slice", "piece", "stick", "whole",
        "bag", "bottle", "box", "bunch", "can", "carton", "container", "jar", "package",
        "dozen", "pint", "qt",
        "small", "medium", "large",
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
    @State private var amountEditingTarget: AmountEditingTarget?
    @State private var stepRows: [DraftStepRow]
    @State private var selectedChapterID: UUID?
    /// Only meaningful in `.create` mode — nil means "use the app's
    /// currently active cookbook," same as before this picker existed.
    /// A separate optional (rather than eagerly reading
    /// `activeCookbookState` here) because `@Environment` isn't populated
    /// yet inside `init` — see `effectiveCookbookID` below for the
    /// fallback that actually resolves it.
    @State private var selectedCookbookID: UUID?
    @State private var tags: [String]
    @State private var newTagText = ""
    @State private var validationMessage: String?

    static let maxVideoURLs = 3
    @State private var videoURLs: [String]
    @State private var newVideoURLText = ""
    @State private var videoURLErrorMessage: String?

    @State private var importText = ""
    @State private var isImporting = false
    @State private var importErrorMessage: String?
    @State private var hasClipboardText = false
    @State private var importedAuthorLineage: String?
    @Environment(\.scenePhase) private var scenePhase
    private let lineImportService: RecipeLineImportServicing = FoundationModelsLineImportService()
    private let userProfileService: UserProfileServicing = FirestoreUserProfileService()

    @State private var isPresentingAuthorPrompt = false
    @State private var authorPromptWasHandled = false

    // MARK: - Inspiration credit (Edit mode only — see canOfferInspirationCredit)
    @State private var isAddingInspirationCredit = false
    @State private var inspirationCreditName = ""
    @State private var inspirationCreditCity = ""
    @State private var inspirationCreditIsUS = true
    @State private var inspirationCreditStateCode = ""
    @State private var inspirationCreditCountry = ""

    #if os(iOS)
    @State private var selectedPhotoItem: PhotosPickerItem?
    #endif
    @State private var heroImageData: Data?
    @State private var removesExistingPhoto = false

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
            _videoURLs = State(initialValue: [])

        case .edit(let recipe):
            _title = State(initialValue: recipe.title)
            _summary = State(initialValue: recipe.summary)
            _yield = State(initialValue: recipe.yield)
            _notes = State(initialValue: recipe.notes)
            _selectedChapterID = State(initialValue: recipe.sectionID)
            _tags = State(initialValue: recipe.tags)
            _videoURLs = State(initialValue: recipe.videoURLs)

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
            _videoURLs = State(initialValue: [])

            // A Discover result only ever hands over one raw string per
            // ingredient (see DiscoveredIngredient.displayText) — never
            // pre-split into quantity/unit/name the way this editor's
            // fields expect. Parsing it here (rather than dumping the
            // whole line into `name`, as this used to do) is what makes
            // the amount wheel actually show the right value instead of
            // staying at zero — see IngredientLineParser's header for why
            // this is the same parser Standardize Recipes now reuses.
            let ingredientDrafts = discovered.ingredients.map { discovered -> DraftIngredientRow in
                let parsed = IngredientLineParser.parse(discovered.displayText, knownUnits: CreateEditRecipeView.commonUnits)
                let name = parsed.rangeUpperText.map { "- \($0) \(parsed.name)" } ?? parsed.name
                return DraftIngredientRow(
                    name: name.trimmingCharacters(in: .whitespaces),
                    quantity: .nearest(to: parsed.quantity),
                    unit: parsed.unit ?? ""
                )
            }
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
                quantity: .nearest(to: ingredient.quantityValue),
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

    var body: some View {
        NavigationStack {
            List {
                Section("Recipe") {
                    TextField("Title", text: $title)
                    TextField("Summary", text: $summary, axis: .vertical)
                    TextField("Yield (e.g. Serves 6)", text: $yield)
                }

                if case .create = mode, ownedCookbooks.count > 1 {
                    Section("Cookbook") {
                        Picker("Cookbook", selection: cookbookSelectionBinding) {
                            ForEach(ownedCookbooks.sorted { $0.sortOrder < $1.sortOrder }) { cookbook in
                                Text(cookbook.title).tag(UUID?.some(cookbook.id))
                            }
                        }
                    }
                }

                if let chapters = effectiveCookbook?.sections, !chapters.isEmpty {
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

                videosSection

                ingredientsSection
                stepsSection
                importSection
                tagsSection

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                }

                inspirationCreditSection

                if let validationMessage {
                    Section {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .listStyle(.plain)
            .potluckHiddenScrollBackground()
            .background(Color.potluckCream)
            .onChange(of: selectedCookbookID) { _, _ in
                // A chapter picked under the old cookbook won't exist in
                // the new one — drop it rather than silently filing the
                // recipe under a chapter that isn't actually shown.
                selectedChapterID = nil
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
            .sheet(isPresented: $isPresentingAuthorPrompt, onDismiss: {
                // Swiping the sheet away without an explicit choice still
                // needs to finish the save — defaults to Anonymous rather
                // than leaving the recipe unsaved.
                if !authorPromptWasHandled {
                    finishSave(authorLineage: "Anonymous")
                }
                authorPromptWasHandled = false
            }) {
                RecipeAuthorPromptView(
                    onSaveWithName: { name, location in
                        authorPromptWasHandled = true
                        isPresentingAuthorPrompt = false
                        if let userID = accountState.currentUserID {
                            Task {
                                try? await accountState.updateDisplayName(name)
                                if let location {
                                    try? await userProfileService.setLocation(location, userID: userID)
                                }
                            }
                        }
                        finishSave(authorLineage: location.map { "\(name) of \($0.formatted)" } ?? name)
                    },
                    onSaveAnonymous: {
                        authorPromptWasHandled = true
                        isPresentingAuthorPrompt = false
                        finishSave(authorLineage: "Anonymous")
                    }
                )
            }
            // Deliberately a modifier on the List itself, not content
            // nested inside it (same shape as isPresentingAuthorPrompt's
            // sheet right above) — see AmountEditingTarget's doc comment
            // for why that distinction is load-bearing here.
            .sheet(item: $amountEditingTarget) { target in
                if let index = ingredientRows.firstIndex(where: { $0.id == target.id }) {
                    AmountWheelPickerSheet(quantity: $ingredientRows[index].quantity) {
                        amountEditingTarget = nil
                    }
                }
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        IngredientsListSection(ingredientRows: $ingredientRows, amountEditingTarget: $amountEditingTarget)
    }

    /// Styled to read as part of the list itself — a green "+" circle
    /// matching the size/weight of the system red delete circle edit mode
    /// already renders on every row above it — rather than a separate
    /// button hanging off the bottom of the section.
    fileprivate static func addRowButton(label: String, action: @escaping () -> Void) -> some View {
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
    fileprivate static func removeRowButton(accessibilityLabel: String, action: @escaping () -> Void) -> some View {
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
                    Self.removeRowButton(accessibilityLabel: "Remove step") {
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

            Self.addRowButton(label: "Add a step") {
                let row = DraftStepRow()
                stepRows.append(row)
                focusedStepRowID = row.id
            }
        }
    }

    // MARK: - Import

    private var importSection: some View {
        Section {
            // lineImportService.isAvailable is always false on tvOS (see
            // FoundationModelsLineImportService), so this branch is never
            // dynamically reached there — but TextEditor below is
            // unavailable on tvOS at compile time regardless of runtime
            // reachability, so the whole section still needs the guard.
            #if !os(tvOS)
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
                        .potluckHiddenScrollBackground()
                        #endif
                        .accessibilityLabel("Paste ingredients and steps to import")
                        .accessibilityIdentifier("importTextEditor")
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )

                HStack {
                    Spacer()
                    Button {
                        Task { await performImport() }
                    } label: {
                        if isImporting {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Label("Import", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(PushableButtonStyle())
                    .disabled(importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isImporting)
                }

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
            #else
            Text("On-device AI import needs Apple Intelligence enabled on this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
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

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let parsedTitle = result.title {
                title = parsedTitle
            }
            if let chapterName = result.chapterName, let matchedChapter = matchingChapter(named: chapterName) {
                selectedChapterID = matchedChapter.id
            }
            if let parsedNotes = result.notes {
                notes = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? parsedNotes
                    : notes + "\n\n" + parsedNotes
            }
            if let authorLineageText = result.authorLineageText {
                importedAuthorLineage = authorLineageText
            }

            ingredientRows.removeAll { $0.isBlank }
            for parsed in result.ingredients {
                ingredientRows.append(DraftIngredientRow(
                    name: parsed.name,
                    quantity: .nearest(to: parsed.quantity),
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

    // MARK: - Inspiration credit

    @ViewBuilder
    private var inspirationCreditSection: some View {
        if let editingRecipe, let inspirationCredit = editingRecipe.inspirationCredit {
            Section("Inspiration Credit") {
                Text(inspirationCredit)
                    .foregroundStyle(.secondary)
            }
        } else if canOfferInspirationCredit {
            Section {
                Toggle("Give Credit for Inspiration", isOn: $isAddingInspirationCredit.animation())
                if isAddingInspirationCredit {
                    TextField("Name", text: $inspirationCreditName)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                    LocationFieldsView(
                        city: $inspirationCreditCity,
                        isUS: $inspirationCreditIsUS,
                        stateCode: $inspirationCreditStateCode,
                        country: $inspirationCreditCountry
                    )
                }
            } footer: {
                Text("Credit someone else's recipe or idea as inspiration for this one — separate from your own name as the recipe's author. This can only be set once, so make sure it's right before saving.")
            }
        }
    }

    /// nil when "Give Credit for Inspiration" wasn't turned on, or was
    /// turned on but left with no name — in either case finishSave leaves
    /// Recipe.inspirationCredit untouched.
    private var draftInspirationCredit: String? {
        guard isAddingInspirationCredit else { return nil }
        let trimmedName = inspirationCreditName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let trimmedCity = inspirationCreditCity.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCity.isEmpty else { return trimmedName }
        let location = UserLocation(
            city: trimmedCity,
            isUS: inspirationCreditIsUS,
            stateCode: inspirationCreditIsUS ? (inspirationCreditStateCode.isEmpty ? nil : inspirationCreditStateCode) : nil,
            country: inspirationCreditIsUS ? nil : inspirationCreditCountry.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        return "\(trimmedName) of \(location.formatted)"
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

    private var videosSection: some View {
        Section {
            ForEach(videoURLs, id: \.self) { url in
                Text(url)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .onDelete { offsets in
                videoURLs.remove(atOffsets: offsets)
            }

            if videoURLs.count < Self.maxVideoURLs {
                HStack {
                    TextField("Paste a YouTube video link", text: $newVideoURLText)
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(addVideoURL)
                    Button("Add", action: addVideoURL)
                        .disabled(newVideoURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let videoURLErrorMessage {
                Text(videoURLErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Videos")
        } footer: {
            Text("Up to \(Self.maxVideoURLs) YouTube links — playable from Cooking Mode.")
        }
    }

    private func addVideoURL() {
        let trimmed = newVideoURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard YouTubeURL.isValidYouTubeURL(trimmed) else {
            videoURLErrorMessage = "That doesn't look like a YouTube link."
            return
        }
        videoURLErrorMessage = nil
        videoURLs.append(trimmed)
        newVideoURLText = ""
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var editingRecipe: Recipe? {
        if case .edit(let recipe) = mode { return recipe }
        return nil
    }

    /// The "Give Credit for Inspiration" option only makes sense once (the
    /// recipe already exists, so this is edit-only) and only when nothing
    /// already occupies that credit: a recipe whose authorLineage came
    /// from an external source (Discover download, or a paste-import's
    /// own "By:" line) already has its credit, and inspirationCredit
    /// itself is immutable once set — see Recipe.swift's field comments.
    private var canOfferInspirationCredit: Bool {
        guard let editingRecipe else { return false }
        return !editingRecipe.authorLineageIsExternal && editingRecipe.inspirationCredit == nil
    }

    private var navigationTitle: String {
        switch mode {
        case .create: return "New Recipe"
        case .edit: return "Edit Recipe"
        case .importing: return "Review & Add Recipe"
        }
    }

    private var ownedCookbooks: [Cookbook] {
        allCookbooks.filter { $0.ownerID == accountState.currentOwnerID }
    }

    /// In `.create` mode this is whatever the "Cookbook" picker has
    /// selected (defaulting to the app's active cookbook until the user
    /// changes it); every other mode keeps the old behavior of always
    /// following the active cookbook.
    private var effectiveCookbookID: UUID? {
        if case .create = mode {
            return selectedCookbookID ?? activeCookbookState.activeCookbookID
        }
        return activeCookbookState.activeCookbookID
    }

    private var effectiveCookbook: Cookbook? {
        ownedCookbooks.first { $0.id == effectiveCookbookID }
    }

    private var cookbookSelectionBinding: Binding<UUID?> {
        Binding(
            get: { effectiveCookbookID },
            set: { selectedCookbookID = $0 }
        )
    }

    /// Matches an AI-parsed chapter name (from an import's "Section:"
    /// label) against the target cookbook's existing chapters — never
    /// creates a new one, per the "leave it blank rather than guess" rule
    /// for anything that can't be confidently resolved.
    private func matchingChapter(named chapterName: String) -> CookbookSection? {
        effectiveCookbook?.sections.first {
            $0.title.caseInsensitiveCompare(chapterName) == .orderedSame
        }
    }

    /// Validates, then resolves this recipe's author lineage (immutable
    /// once set — never touched again in `.edit` mode) before actually
    /// constructing/saving anything: an imported "By:" line wins if
    /// present, otherwise the signed-in user's own name+location if
    /// they've set one, otherwise the dismissable author prompt (which
    /// itself calls `finishSave` once resolved).
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
        // A brand-new account has no cookbook until the user creates or
        // restores one (see the Getting Started dashboard card) — without
        // this, a .create/.importing save with nowhere to file into
        // still "succeeds" but the recipe is orphaned: cookbookID nil,
        // permanently unreachable from any recipe list in the app.
        if case .edit = mode {} else {
            guard effectiveCookbookID != nil else {
                validationMessage = "Create a cookbook first, then add this recipe to it."
                return
            }
        }
        validationMessage = nil

        guard case .edit = mode else {
            if let importedAuthorLineage {
                finishSave(authorLineage: importedAuthorLineage)
            } else if let displayName = accountState.currentUserDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !displayName.isEmpty {
                if let userID = accountState.currentUserID {
                    Task {
                        let location = try? await userProfileService.fetchLocation(userID: userID)
                        finishSave(authorLineage: location.map { "\(displayName) of \($0.formatted)" } ?? displayName)
                    }
                } else {
                    finishSave(authorLineage: displayName)
                }
            } else {
                isPresentingAuthorPrompt = true
            }
            return
        }
        finishSave(authorLineage: nil)
    }

    private func finishSave(authorLineage: String?) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)

        let recipe: Recipe
        switch mode {
        case .create:
            recipe = Recipe(ownerID: accountState.currentOwnerID, title: trimmedTitle, sourceType: .manual)
            recipe.cookbookID = effectiveCookbookID
            recipe.authorLineage = authorLineage
            // True only when the paste-import's AI parsing actually pulled
            // a "By:" line out of the pasted text — anything else here
            // (self-entered display name, the author prompt, Anonymous) is
            // the owner's own self-attribution, not an external source.
            recipe.authorLineageIsExternal = importedAuthorLineage != nil
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
            // Immutable once set — only ever assigned when it's still nil,
            // never overwritten on a later edit.
            if recipe.inspirationCredit == nil, let draftInspirationCredit {
                recipe.inspirationCredit = draftInspirationCredit
            }
        case .importing(let discovered):
            recipe = Recipe(ownerID: accountState.currentOwnerID, title: trimmedTitle, sourceType: .webImport)
            recipe.cookbookID = activeCookbookState.activeCookbookID
            recipe.authorLineage = authorLineage
            // A Discover download is always an external source, regardless
            // of exactly how authorLineage itself got resolved.
            recipe.authorLineageIsExternal = true
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
        recipe.videoURLs = videoURLs
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

        do {
            try modelContext.save()
            dismiss()
        } catch {
            validationMessage = "Couldn't save this recipe: \(error.localizedDescription)"
        }
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
            let quantityText = row.quantity.displayText
            let trimmedUnit = row.unit.trimmingCharacters(in: .whitespacesAndNewlines)

            return Ingredient(
                displayText: Self.composeDisplayText(name: trimmedName, quantityText: quantityText, unit: trimmedUnit),
                name: trimmedName.isEmpty ? quantityText : trimmedName,
                quantityValue: row.quantity.quantityValue,
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
