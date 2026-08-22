//
//  RecipeDetailView.swift
//  cookbook
//

import SwiftUI
import SwiftData

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var modelContext
    @Environment(AccountState.self) private var accountState
    @State private var isPresentingEdit = false
    @State private var isPresentingCookingMode = false
    @State private var isPresentingPublish = false
    @State private var isPresentingShareWithFriend = false
    @State private var cartToastMessage: String?
    #if os(iOS)
    /// Drives the Videos section's per-icon playback sheet — set to the
    /// tapped video's own URL string, nil when no sheet is up.
    @State private var selectedVideoURLString: String?
    /// Separate from isPresentingCookingMode (the toolbar's own "Start
    /// Cooking" entry point) — this one opens Cooking Mode with "Ready to
    /// Continue" instead, since reaching Cooking Mode from the Videos
    /// section implies a cook already in progress, not a fresh start.
    @State private var isPresentingCookingModeToContinue = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if !recipe.summary.isEmpty {
                    Text(recipe.summary)
                        .font(.body)
                }

                metadataRow

                if !recipe.ingredientSections.isEmpty {
                    HStack {
                        sectionHeader("Ingredients")
                        Spacer()
                        Button("Add all to cart") {
                            addAllIngredientsToCart()
                        }
                        .font(.subheadline)
                    }
                    ForEach(recipe.ingredientSections.sorted(by: { $0.sortOrder < $1.sortOrder })) { section in
                        ingredientSection(section)
                    }
                }

                if !recipe.stepSections.isEmpty {
                    sectionHeader("Steps")
                    ForEach(recipe.stepSections.sorted(by: { $0.sortOrder < $1.sortOrder })) { section in
                        stepSection(section)
                    }
                }

                sectionHeader("Notes")
                if recipe.notes.isEmpty {
                    Text("No notes yet.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(recipe.notes)
                }

                #if os(iOS)
                if !recipe.videoURLs.isEmpty {
                    videosSection
                }
                #endif

                NutritionSummaryView(
                    calories: recipe.calories,
                    proteinGrams: recipe.proteinGrams,
                    fatGrams: recipe.fatGrams,
                    carbsGrams: recipe.carbsGrams,
                    sugarGrams: recipe.sugarGrams,
                    fiberGrams: recipe.fiberGrams,
                    sodiumMilligrams: recipe.sodiumMilligrams
                )
            }
            .padding()
        }
        .background(Color.potluckCream)
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Love (Favorite) only — Like doesn't apply to a personal
                // recipe (nothing to aggregate a count across); the shared-
                // cookbook counterpart lives in CommunityCookbookRecipesView instead,
                // next to each published recipe's real like count.
                Button {
                    recipe.isFavorite.toggle()
                    recipe.updatedAt = .now
                    saveOrRevert { recipe.isFavorite.toggle() }
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                }
                .accessibilityLabel(recipe.isFavorite ? "Remove from Favorites" : "Add to Favorites")

                Button {
                    isPresentingCookingMode = true
                } label: {
                    Label("Start Cooking", systemImage: "flame")
                }
                .accessibilityLabel("Start Cooking")

                // An explicit menu, not iOS's automatic toolbar overflow —
                // deliberately not relying on that for Edit/Share/Publish.
                Menu {
                    Button {
                        isPresentingEdit = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }

                    #if !os(tvOS)
                    ShareLink(item: RecipeTextFormatter.plainText(for: recipe)) {
                        Label("Share Recipe", systemImage: "square.and.arrow.up")
                    }
                    #endif

                    Button {
                        isPresentingPublish = true
                    } label: {
                        Label("Publish to a Community Cookbook", systemImage: "person.3")
                    }

                    Button {
                        isPresentingShareWithFriend = true
                    } label: {
                        Label("Share with a Friend", systemImage: "paperplane")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More options")
            }
        }
        .sheet(isPresented: $isPresentingEdit) {
            CreateEditRecipeView(mode: .edit(recipe))
        }
        .sheet(isPresented: $isPresentingCookingMode) {
            CookingModeView(recipe: recipe)
        }
        #if os(iOS)
        .sheet(isPresented: Binding(
            get: { selectedVideoURLString != nil },
            set: { isPresented in if !isPresented { selectedVideoURLString = nil } }
        )) {
            if let selectedVideoURLString {
                RecipeVideoPlayerSheet(videoURLString: selectedVideoURLString)
            }
        }
        .sheet(isPresented: $isPresentingCookingModeToContinue) {
            CookingModeView(recipe: recipe, startButtonLabel: "Ready to Continue")
        }
        #endif
        .sheet(isPresented: $isPresentingPublish) {
            PublishToFamilyCookbookView(
                recipe: recipe,
                groupsService: FirestoreGroupsService(),
                publicationsService: FirestorePublicationsService(),
                photoUploadService: FirebaseRecipePhotoUploadService(),
                entitlementService: FirestoreEntitlementService()
            )
        }
        .sheet(isPresented: $isPresentingShareWithFriend) {
            ShareRecipeWithFriendView(
                recipe: recipe,
                friendsService: FirestoreFriendsService(),
                sharedRecipesService: FirestoreSharedRecipesService()
            )
        }
        .cartToast($cartToastMessage)
    }

    private func addAllIngredientsToCart() {
        let ownerID = accountState.currentOwnerID
        let sourceRecipeID = recipe.id.uuidString
        do {
            for section in recipe.ingredientSections {
                for ingredient in section.ingredients {
                    try CartItemStore.addFromRecipe(
                        ownerID: ownerID,
                        displayText: ingredient.displayText,
                        quantityValue: ingredient.quantityValue,
                        unit: ingredient.unit,
                        sourceRecipeID: sourceRecipeID,
                        sourceRecipeTitleSnapshot: recipe.title,
                        sourceIngredientID: ingredient.id,
                        in: modelContext
                    )
                }
            }
            showCartToast("Added all ingredients to cart")
        } catch {
            showCartToast("Couldn't add all ingredients to cart")
        }
    }

    /// Favorite/Like toggle first, save second — if the save throws, undo
    /// the toggle so the UI doesn't claim a change that didn't persist,
    /// and tell the user via the existing cart-toast overlay (a generic
    /// bottom toast despite the name, not cart-specific).
    private func saveOrRevert(undo: () -> Void) {
        do {
            try modelContext.save()
        } catch {
            undo()
            showCartToast("Couldn't save — try again")
        }
    }

    private func showCartToast(_ message: String) {
        cartToastMessage = message
        Task {
            try? await Task.sleep(for: .seconds(2))
            if cartToastMessage == message {
                cartToastMessage = nil
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text(recipe.title)
                .font(.potluckHeadline(26))
                .foregroundStyle(Color.potluckDeepTeal)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            heroImage

            // Owner/credit line, never an editable field here. "Inspired
            // by" only shows when the recipe actually has a stamped
            // authorLineage (imported "By:" line, or the creator's own
            // name/location if they set one) — otherwise it's just "You."
            Label(lineageLabelText, systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Credit: \(lineageLabelText)")

            // Copy-to-Personal lineage (PRD §6, LIN-004) — never editable,
            // never hideable by the owner. Distinct from the credit line
            // above: that's "who to thank," this is "which cookbook this
            // was copied from."
            if let sharedFromText {
                Label(sharedFromText, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Shared from: \(sharedFromText)")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var lineageLabelText: String {
        if let lineage = recipe.authorLineage?.trimmingCharacters(in: .whitespacesAndNewlines), !lineage.isEmpty {
            return "Inspired by \(lineage)"
        }
        return "You"
    }

    private var sharedFromText: String? {
        guard let group = recipe.sourceGroupSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines), !group.isEmpty else {
            return nil
        }
        if let owner = recipe.sourceOwnerSnapshot?.trimmingCharacters(in: .whitespacesAndNewlines), !owner.isEmpty {
            return "Shared from \(owner) in \(group)"
        }
        return "Shared from \(group)"
    }

    @ViewBuilder
    private var heroImage: some View {
        #if os(iOS)
        if let filename = recipe.heroPhotoFilename, let data = PhotoStore.data(for: filename), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
                .potluckCardShadow()
                .accessibilityLabel("Photo of \(recipe.title)")
        }
        #endif
    }

    private var metadataRow: some View {
        HStack(spacing: 16) {
            if !recipe.yield.isEmpty {
                Label(recipe.yield, systemImage: "person.2")
            }
            if let totalTime = recipe.totalTimeMinutes {
                Label("\(totalTime) min", systemImage: "clock")
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    #if os(iOS)
    /// One "play.rectangle" icon per saved video (same icon Cooking Mode's
    /// own toolbar uses for the same purpose) — tapping icon N plays video
    /// N directly, no picker needed since the icon itself is the choice.
    /// "View In Cooking Mode" underneath is a second way to reach the same
    /// videos (and everything else Cooking Mode offers) without leaving
    /// this screen to find the toolbar's own Start Cooking button.
    private var videosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Videos")
            HStack(spacing: 20) {
                ForEach(Array(recipe.videoURLs.enumerated()), id: \.offset) { index, url in
                    Button {
                        selectedVideoURLString = url
                    } label: {
                        Image(systemName: "play.rectangle")
                            .font(.title2)
                    }
                    .accessibilityLabel("Play video \(index + 1)")
                }
                Spacer()
            }

            Button {
                isPresentingCookingModeToContinue = true
            } label: {
                // Text before the icon, per spec — SwiftUI's Label always
                // puts the icon first, so this is a plain HStack instead.
                HStack(spacing: 6) {
                    Text("View This Recipe in COOKING MODE")
                    Image(systemName: "flame")
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("View This Recipe in Cooking Mode")
        }
    }
    #endif

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 8)
    }

    private func ingredientSection(_ section: IngredientSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let heading = section.heading, !heading.isEmpty {
                Text(heading)
                    .font(.headline)
            }
            ForEach(section.ingredients.sorted(by: { $0.sortOrder < $1.sortOrder })) { ingredient in
                HStack(alignment: .top) {
                    Text(ingredient.displayText)
                    if ingredient.isOptional {
                        Text("(optional)")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AddToCartButton(
                        ownerID: accountState.currentOwnerID,
                        sourceRecipeID: recipe.id.uuidString,
                        sourceRecipeTitleSnapshot: recipe.title,
                        sourceIngredientID: ingredient.id,
                        displayText: ingredient.displayText,
                        quantityValue: ingredient.quantityValue,
                        unit: ingredient.unit
                    )
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func stepSection(_ section: StepSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let heading = section.heading, !heading.isEmpty {
                Text(heading)
                    .font(.headline)
            }
            ForEach(Array(section.steps.sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .fontWeight(.semibold)
                    Text(step.text)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Step \(index + 1): \(step.text)")
            }
        }
    }
}

#if os(iOS)
/// A single video, no picker — the Videos section's own icon row is
/// already the picker (tapping icon N opens this with that video's URL
/// directly). Mirrors CookingModeVideoSheet's single-video rendering.
private struct RecipeVideoPlayerSheet: View {
    let videoURLString: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack {
                if let videoID = YouTubeURL.videoID(from: videoURLString) {
                    YouTubePlayerView(videoID: videoID)
                        .id(videoID)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .potluckCardShadow()
                        .padding()
                } else {
                    ContentUnavailableView(
                        "Couldn't Load Video",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This link doesn't look like a valid YouTube video anymore.")
                    )
                }
                Spacer()
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif

#Preview {
    RecipeDetailPreviewContainer()
}

private struct RecipeDetailPreviewContainer: View {
    @State private var recipe = Recipe(ownerID: "preview", title: "Skillet Cornbread", summary: "Crispy edges, tender center.")

    var body: some View {
        NavigationStack {
            RecipeDetailView(recipe: recipe)
        }
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(ActiveCookbookState())
    }
}
