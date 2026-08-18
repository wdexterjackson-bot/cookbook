//
//  RecipeListView.swift
//  cookbook
//

import SwiftUI
import SwiftData

private extension ToolbarItemPlacement {
    /// .secondaryAction is unavailable on tvOS (no overflow-menu concept
    /// there) — .automatic lets the system place these sensibly instead.
    static var recipeListSecondaryAction: ToolbarItemPlacement {
        #if os(tvOS)
        .automatic
        #else
        .secondaryAction
        #endif
    }
}

/// `id` is a stable key (a section's own UUID, or a fixed sentinel for the
/// synthetic "Other"/flat-list groups) — this used to be a plain tuple
/// rendered via `ForEach(..., id: \.offset)`, which crashed when deleting a
/// chapter: removing one group shifts every later group's array position,
/// so SwiftUI's offset-keyed diffing reused a view identity (and its
/// DisclosureGroup expand/collapse state, and its `.swipeActions` closures
/// capturing a specific CookbookSection) for what was now a *different*
/// chapter at that position — undefined behavior, observed as a real crash
/// deleting an empty chapter (2026-08-08). A real Identifiable type keyed
/// by section id sidesteps this: each group's identity now follows its
/// actual chapter, not its position in the array.
private struct RecipeSectionGroup: Identifiable {
    var id: String
    var title: String?
    var section: CookbookSection?
    var recipes: [Recipe]
}

struct RecipeListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @Environment(ActiveCookbookState.self) private var activeCookbookState
    @Query(sort: \Recipe.updatedAt, order: .reverse) private var allRecipes: [Recipe]
    @Query private var allCookbooks: [Cookbook]
    @State private var isPresentingCreateRecipe = false
    @State private var isPresentingFilters = false
    @State private var isPresentingAccount = false
    @State private var isPresentingCookbookSwitcher = false
    @State private var criteria = RecipeFilterCriteria()
    /// Empty by default — every chapter starts collapsed. Keyed by a stable
    /// identity (section id, or the group's title for "Other," the
    /// synthetic group with no real CookbookSection) rather than by title
    /// alone — renaming a chapter (see sectionPendingEdit) must not reset
    /// its expanded/collapsed state.
    @State private var expandedChapterKeys: Set<String> = []
    /// Session-only override (not persisted) — forces chapters to sort by
    /// recipe count even if the user has previously drag-reordered them.
    /// Off just falls back to Cookbook.chaptersManuallyReordered's own
    /// default behavior, unchanged.
    @State private var sortChaptersByRecipeCount = false
    @State private var sectionPendingEdit: CookbookSection?
    @State private var editedSectionTitle = ""
    @State private var sectionPendingDeletion: CookbookSection?

    private var activeCookbook: Cookbook? {
        allCookbooks.first { $0.id == activeCookbookState.activeCookbookID }
    }

    /// Recipes belonging to whichever identity is currently active on this
    /// device (signed-in account, or the local guest identity) — owner-key
    /// scoping so a second person signing in on a shared device never sees
    /// the first person's recipes — AND filed under the currently active
    /// Cookbook specifically, now that an owner can have more than one.
    private var ownedRecipes: [Recipe] {
        allRecipes.filter { $0.ownerID == accountState.currentOwnerID && $0.cookbookID == activeCookbookState.activeCookbookID }
    }

    private var filteredRecipes: [Recipe] {
        RecipeSearch.apply(criteria, to: ownedRecipes)
    }

    /// Groups filteredRecipes by the active cookbook's configured chapters,
    /// in chapter order, with a trailing "Other" group for anything with no
    /// (or a since-removed/since-deleted) section. A cookbook with zero
    /// configured chapters falls back to one untitled group — today's flat
    /// list. `section` is nil for that flat-list group and for "Other" —
    /// both are synthetic, not a real CookbookSection — which is what the
    /// chapter-header swipe actions (Edit/Delete) key off of to only ever
    /// show on a real chapter.
    ///
    /// While just browsing (no search text, no filters), every configured
    /// chapter shows even with zero recipes — chapters are chosen
    /// deliberately at cookbook creation, so an empty one should still be
    /// visible as a place to add to, not disappear until it has content.
    /// An active search still hides chapters with no matches, since
    /// showing every empty chapter there would bury the actual results.
    ///
    /// Chapter order: until the user has actually dragged to reorder
    /// chapters in CookbookConfigurationView (Cookbook.chaptersManuallyReordered),
    /// chapters default-sort by recipe count, highest first, recomputed
    /// live as recipes are added — not the fixed catalog/creation order.
    /// Once the user reorders once, that explicit order (CookbookSection.sortOrder)
    /// is respected from then on and recipe counts no longer move things
    /// around on them — unless sortChaptersByRecipeCount (the Sort & Filter
    /// menu's "# of Recipes" toggle) is on, which always wins.
    private var groupedBySection: [RecipeSectionGroup] {
        guard let activeCookbook, !activeCookbook.sections.isEmpty else {
            return [RecipeSectionGroup(id: "flat", title: nil, section: nil, recipes: filteredRecipes)]
        }
        let isBrowsing = criteria.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !criteria.hasActiveFilters

        var groups: [RecipeSectionGroup] = []
        let sortedSections: [CookbookSection]
        if !sortChaptersByRecipeCount && activeCookbook.chaptersManuallyReordered {
            sortedSections = activeCookbook.sections.sorted { $0.sortOrder < $1.sortOrder }
        } else {
            var countBySectionID: [UUID: Int] = [:]
            for recipe in ownedRecipes {
                guard let sectionID = recipe.sectionID else { continue }
                countBySectionID[sectionID, default: 0] += 1
            }
            sortedSections = activeCookbook.sections.sorted { lhs, rhs in
                let lhsCount = countBySectionID[lhs.id] ?? 0
                let rhsCount = countBySectionID[rhs.id] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return lhs.sortOrder < rhs.sortOrder
            }
        }
        for section in sortedSections {
            let recipesInSection = filteredRecipes.filter { $0.sectionID == section.id }
            if !recipesInSection.isEmpty || isBrowsing {
                groups.append(RecipeSectionGroup(id: section.id.uuidString, title: section.title, section: section, recipes: recipesInSection))
            }
        }

        let knownSectionIDs = Set(sortedSections.map(\.id))
        let unfiled = filteredRecipes.filter { recipe in
            guard let sectionID = recipe.sectionID else { return true }
            return !knownSectionIDs.contains(sectionID)
        }
        if !unfiled.isEmpty {
            groups.append(RecipeSectionGroup(id: "other", title: "Other", section: nil, recipes: unfiled))
        }
        return groups
    }

    var body: some View {
        // No NavigationStack here — this view is always pushed as a
        // destination now (from CookbooksHubView or HomeView's own
        // NavigationStack), never a tab root. A NavigationStack nested
        // inside another one silently breaks the push: the destination
        // never actually appears, and the parent's list just sits there
        // as if the tap did nothing.
        Group {
            VStack(spacing: 0) {
                cookbookHeader
                recipeListOrEmptyState
            }
            .background(Color.potluckCream)
            .searchable(text: $criteria.searchText, prompt: "Search recipes, ingredients, tags")
            .navigationTitle("")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { recipeListToolbar }
            .sheet(isPresented: $isPresentingCreateRecipe) {
                CreateEditRecipeView(mode: .create)
            }
            .sheet(isPresented: $isPresentingFilters) {
                RecipeFilterSheet(criteria: $criteria, availableOptions: RecipeFilterOptions(recipes: ownedRecipes))
            }
            .sheet(isPresented: $isPresentingCookbookSwitcher) {
                CookbooksListView()
            }
            .sheet(isPresented: $isPresentingAccount) {
                AccountView()
            }
            .alert(
                "Rename Chapter",
                isPresented: Binding(
                    get: { sectionPendingEdit != nil },
                    set: { if !$0 { sectionPendingEdit = nil } }
                )
            ) {
                TextField("Chapter Name", text: $editedSectionTitle)
                Button("Save", action: renameSection)
                Button("Cancel", role: .cancel) { sectionPendingEdit = nil }
            }
            .alert(
                "Delete Chapter?",
                isPresented: Binding(
                    get: { sectionPendingDeletion != nil },
                    set: { if !$0 { sectionPendingDeletion = nil } }
                )
            ) {
                Button("Delete Chapter", role: .destructive) {
                    if let section = sectionPendingDeletion {
                        deleteSection(section)
                    }
                    sectionPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { sectionPendingDeletion = nil }
            } message: {
                Text(deleteSectionConfirmationMessage)
            }
        }
    }

    /// Broken out of `body` — folded inline, this List/ForEach/Section
    /// nest (each chapter a Section with a header row + conditionally
    /// shown recipe rows) pushed the whole body expression over the
    /// type-checker's budget on tvOS ("unable to type-check this
    /// expression in reasonable time"), even though nothing here is
    /// individually complex — isolating it in its own property keeps each
    /// piece cheap to infer separately.
    @ViewBuilder
    private var recipeListOrEmptyState: some View {
        Group {
            if ownedRecipes.isEmpty {
                ContentUnavailableView(
                    "No Recipes Yet",
                    systemImage: "fork.knife",
                    description: Text("Tap the + button to add your first recipe to \(activeCookbook?.title ?? "your cookbook").")
                )
            } else if filteredRecipes.isEmpty {
                ContentUnavailableView(
                    "No Matching Recipes",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term or clear your filters.")
                )
            } else {
                List {
                    if criteria.hasActiveFilters {
                        Section {
                            activeFilterChips
                        }
                        .listRowInsets(EdgeInsets())
                    }
                    ForEach(groupedBySection) { group in
                        if let title = group.title {
                            // A cookbook with configured chapters shows
                            // each as a collapsed heading by default —
                            // tap to expand and see its recipes,
                            // rather than one long scroll of every
                            // chapter's recipes at once.
                            //
                            // Deliberately NOT SwiftUI's DisclosureGroup
                            // here — a DisclosureGroup placed directly
                            // in a List, with .swipeActions attached to
                            // it, leaks those swipe actions onto its
                            // expanded child rows too (observed
                            // 2026-08-09: swiping a recipe row showed
                            // the chapter's own Edit/Delete alongside
                            // the recipe's own Delete). A plain header
                            // row plus a conditionally-shown ForEach,
                            // both direct children of the Section, has
                            // no such ambiguity — the header's
                            // .swipeActions can only ever apply to the
                            // header's own row.
                            Section {
                                chapterHeaderRowWithSwipeActions(group: group, title: title)
                                if expandedChapterKeys.contains(group.section?.id.uuidString ?? title) {
                                    recipeRows(group.recipes)
                                }
                            }
                        } else {
                            // No chapters configured — today's flat
                            // list, unchanged.
                            Section {
                                recipeRows(group.recipes)
                            }
                        }
                    }
                }
                // Chapters are shown as separate List Sections (so
                // each gets its own DisclosureGroup), which by
                // default puts a noticeable gap between them —
                // cut down to a fraction of that so the chapter
                // list itself reads as compact, not spaced out.
                #if os(iOS)
                .listSectionSpacing(2)
                #endif
            }
        }
        .potluckHiddenScrollBackground()
        .background(Color.potluckCream)
    }

    @ViewBuilder
    private var cookbookHeader: some View {
        if let activeCookbook {
            VStack(spacing: 8) {
                Text(activeCookbook.title)
                    .font(.potluckHeadline(24))
                    .foregroundStyle(Color.potluckDeepTeal)
                    .multilineTextAlignment(.center)

                cookbookHeaderCard(activeCookbook)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
    }

    /// A custom cover image wins if there is one; otherwise this card
    /// falls back to the plain color, deliberately skipping a chosen
    /// Cover Style here — there's no default image sized/cropped for
    /// this specific placement yet (see CookbookConfigurationView's
    /// "Cover Style" footer). Home's cookbook shelf is where a style
    /// actually shows.
    @ViewBuilder
    private func cookbookHeaderCard(_ cookbook: Cookbook) -> some View {
        Group {
            #if os(iOS)
            if let filename = cookbook.coverImageFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .accessibilityHidden(true)
            } else {
                Color(hex: cookbook.coverColorHex)
            }
            #else
            Color(hex: cookbook.coverColorHex)
            #endif
        }
        .frame(height: 140)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
        .potluckCardShadow()
        .padding(.horizontal)
    }

    private var activeFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let course = criteria.course {
                    filterChip("Course: \(course)") { criteria.course = nil }
                }
                if let cuisine = criteria.cuisine {
                    filterChip("Cuisine: \(cuisine)") { criteria.cuisine = nil }
                }
                if let tag = criteria.tag {
                    filterChip("Tag: \(tag)") { criteria.tag = nil }
                }
                if let dietaryLabel = criteria.dietaryLabel {
                    filterChip("Diet: \(dietaryLabel)") { criteria.dietaryLabel = nil }
                }
                if let excludedAllergen = criteria.excludedAllergen {
                    filterChip("No \(excludedAllergen)") { criteria.excludedAllergen = nil }
                }
                if criteria.favoritesOnly {
                    filterChip("Favorites") { criteria.favoritesOnly = false }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    private func filterChip(_ text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.caption)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .accessibilityLabel("Remove filter: \(text)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    private func deleteRecipe(_ recipe: Recipe) {
        let store = SwiftDataRecipeStore(context: modelContext)
        try? store.delete(recipe)
    }

    private func renameSection() {
        guard let section = sectionPendingEdit else { return }
        let trimmed = editedSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        section.title = trimmed
        activeCookbook?.updatedAt = .now
        try? modelContext.save()
        sectionPendingEdit = nil
    }

    private var deleteSectionConfirmationMessage: String {
        guard let section = sectionPendingDeletion else { return "" }
        let count = ownedRecipes.filter { $0.sectionID == section.id }.count
        let recipeWord = count == 1 ? "recipe" : "recipes"
        return "Delete \"\(section.title)\"? Its \(count) \(recipeWord) will move to Other — no recipes are deleted."
    }

    /// Never deletes a recipe — every recipe in this section is unfiled
    /// (sectionID set to nil) so it surfaces in the "Other" group instead.
    private func deleteSection(_ section: CookbookSection) {
        for recipe in ownedRecipes where recipe.sectionID == section.id {
            recipe.sectionID = nil
            recipe.updatedAt = .now
        }
        activeCookbook?.sections.removeAll { $0.id == section.id }
        modelContext.delete(section)
        activeCookbook?.updatedAt = .now
        try? modelContext.save()
    }

    /// Broken out of `body` — folded inline, this toolbar's nested
    /// Menu/Picker pushed the whole body expression over the
    /// type-checker's budget on tvOS ("unable to type-check this
    /// expression in reasonable time"), the same complexity-isolation
    /// reasoning as chapterHeaderRowWithSwipeActions below.
    @ToolbarContentBuilder
    private var recipeListToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isPresentingCreateRecipe = true
            } label: {
                Label("Add Recipe", systemImage: "plus")
            }
            .accessibilityLabel("Add Recipe")
        }
        ToolbarItem(placement: .recipeListSecondaryAction) {
            Button {
                isPresentingCookbookSwitcher = true
            } label: {
                Label("Cookbooks", systemImage: "books.vertical")
            }
            .accessibilityLabel("Switch or manage cookbooks")
        }
        ToolbarItem(placement: .recipeListSecondaryAction) {
            Menu {
                Picker("Sort", selection: $criteria.sort) {
                    ForEach(RecipeSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                if let activeCookbook, !activeCookbook.sections.isEmpty {
                    Toggle(isOn: $sortChaptersByRecipeCount) {
                        Label("Sort Chapters by # of Recipes", systemImage: "number")
                    }
                }
                Button {
                    isPresentingFilters = true
                } label: {
                    Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                }
            } label: {
                Label("Sort & Filter", systemImage: "line.3.horizontal.decrease.circle")
            }
            .accessibilityLabel("Sort and filter recipes")
        }
        ToolbarItem(placement: .recipeListSecondaryAction) {
            Button {
                isPresentingAccount = true
            } label: {
                Image(systemName: accountState.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
            }
            .accessibilityLabel(accountState.isSignedIn ? "Account, signed in" : "Account, not signed in")
        }
    }

    /// Manual stand-in for DisclosureGroup's header row — see the comment
    /// at this view's call site for why DisclosureGroup itself isn't used
    /// inside this List.
    private func chapterHeaderRow(group: RecipeSectionGroup, title: String) -> some View {
        let key = group.section?.id.uuidString ?? title
        let isExpanded = expandedChapterKeys.contains(key)
        return Button {
            withAnimation {
                if isExpanded {
                    expandedChapterKeys.remove(key)
                } else {
                    expandedChapterKeys.insert(key)
                }
            }
        } label: {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(group.recipes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// Broken out from the chapter ForEach in `body` — folding this
    /// #if/.swipeActions directly into that already-large expression
    /// pushed the type-checker over budget ("unable to type-check this
    /// expression in reasonable time"), even though nothing here is
    /// individually complex; isolating it in its own function keeps each
    /// piece cheap to infer separately.
    @ViewBuilder
    private func chapterHeaderRowWithSwipeActions(group: RecipeSectionGroup, title: String) -> some View {
        chapterHeaderRow(group: group, title: title)
            // swipeActions itself is unavailable on tvOS — chapter
            // Edit/Delete isn't offered on this platform.
            #if !os(tvOS)
            .swipeActions {
                // Only a real chapter (not the synthetic "Other" group)
                // can be edited/deleted.
                if let section = group.section {
                    Button("Delete", role: .destructive) {
                        sectionPendingDeletion = section
                    }
                    Button("Edit") {
                        editedSectionTitle = section.title
                        sectionPendingEdit = section
                    }
                    .tint(.blue)
                }
            }
            #endif
    }

    @ViewBuilder
    private func recipeRows(_ recipes: [Recipe]) -> some View {
        ForEach(recipes) { recipe in
            NavigationLink {
                RecipeDetailView(recipe: recipe)
            } label: {
                RecipeRow(recipe: recipe)
            }
            // swipeActions itself is unavailable on tvOS — recipe deletion
            // from this list isn't offered on this platform.
            #if !os(tvOS)
            .swipeActions {
                Button("Delete", role: .destructive) {
                    deleteRecipe(recipe)
                }
            }
            #endif
        }
    }
}

/// Not private — reused by FavoriteRecipesView so the cross-cookbook
/// favorites list shows recipes with the same thumbnail/metadata styling
/// as every other recipe list in the app.
struct RecipeRow: View {
    let recipe: Recipe

    /// Unscoped — every call site (RecipeListView, SearchHubView,
    /// FavoriteRecipesView) shows recipes that can belong to different
    /// cookbooks/chapters, and the section count here is small enough
    /// that a predicate isn't worth the complexity of threading a
    /// resolved icon through three different callers instead.
    @Query private var allSections: [CookbookSection]

    /// The chapter this recipe is filed under, if any and if it has an
    /// icon assigned — used only as the placeholder when there's no real
    /// hero photo; a recipe's own photo always wins, unchanged.
    private var sectionIcon: CookbookSectionIcon? {
        guard let sectionID = recipe.sectionID,
              let section = allSections.first(where: { $0.id == sectionID }) else { return nil }
        return CookbookSectionIconCatalog.icon(named: section.iconAssetName)
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.headline)
                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if recipe.calories != nil || !recipe.dietaryLabels.isEmpty {
                    metadataRow
                }
            }
            Spacer()
            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Favorite")
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var thumbnail: some View {
        #if os(iOS)
        if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
        } else {
            placeholderThumbnail
        }
        #else
        placeholderThumbnail
        #endif
    }

    @ViewBuilder
    private var placeholderThumbnail: some View {
        if let sectionIcon {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(sectionIcon.assetName)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(Color.accentColor)
                }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 6) {
            if let calories = recipe.calories {
                Text("\(calories.formatted(.number.precision(.fractionLength(0)))) cal")
            }
            ForEach(recipe.dietaryLabels.prefix(2), id: \.self) { label in
                Text(label.capitalized)
            }
        }
        .font(.caption)
        .foregroundStyle(Color.accentColor)
    }
}

#Preview {
    NavigationStack {
        RecipeListView()
    }
    .modelContainer(for: Recipe.self, inMemory: true)
    .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
}
