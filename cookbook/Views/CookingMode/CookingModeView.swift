//
//  CookingModeView.swift
//  cookbook
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

struct CookingModeView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(AccountState.self) private var accountState
    @Environment(CookingSessionState.self) private var cookingSessionState

    /// Gates the step pager behind CookingModePrepReviewView — false until
    /// the user taps "Start Cooking" there. Not persisted across launches
    /// on purpose: reopening Cooking Mode for a recipe always starts back
    /// at the prep review, even mid-recipe (CookingSessionState's saved
    /// currentStepIndex still resumes correctly once past this gate).
    @State private var hasStartedCooking = false
    @State private var currentStepIndex = 0
    @State private var checkedStepIDs: Set<UUID> = []
    @State private var checkedIngredientIDs: Set<UUID> = []
    @State private var servingMultiplier: Double = 1
    @State private var keepsScreenAwake = true
    @State private var isPresentingIngredients = false
    @State private var isPresentingTimers = false
    @State private var isPresentingVideos = false
    @State private var timerManager = CookingTimerManager()
    /// Shared by every step page (not one independent random value each) —
    /// changes once per step, on currentStepIndex changing, so all
    /// currently/adjacently-rendered pages agree on one background at a
    /// time rather than looking mismatched mid-swipe. See
    /// CookingModeBackgroundCatalog.swift, shared with the video sheet.
    @State private var currentBackgroundImageName = CookingModeBackgroundCatalog.randomName(excluding: nil)

    private var flattenedSteps: [(section: String?, step: Step)] {
        let sortedSections = recipe.stepSections.sorted { $0.sortOrder < $1.sortOrder }
        return sortedSections.flatMap { section -> [(section: String?, step: Step)] in
            let sortedSteps = section.steps.sorted { $0.sortOrder < $1.sortOrder }
            return sortedSteps.map { (section.heading, $0) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if flattenedSteps.isEmpty {
                    ContentUnavailableView(
                        "No Steps to Cook",
                        systemImage: "flame",
                        description: Text("Add steps to this recipe to use cooking mode.")
                    )
                } else if !hasStartedCooking {
                    CookingModePrepReviewView(recipe: recipe, servingMultiplier: $servingMultiplier) {
                        hasStartedCooking = true
                    }
                } else {
                    stepPager
                }
            }
            .background(Color.potluckCream)
            .safeAreaInset(edge: .top) {
                CookingModeActiveTimersBanner(manager: timerManager)
            }
            .navigationTitle(recipe.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { finish() }
                }
                if hasStartedCooking {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            isPresentingIngredients = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("Show ingredients")

                        Button {
                            isPresentingTimers = true
                        } label: {
                            Image(systemName: "timer")
                        }
                        .accessibilityLabel(timersButtonAccessibilityLabel)

                        #if os(iOS)
                        if !recipe.videoURLs.isEmpty {
                            Button {
                                isPresentingVideos = true
                            } label: {
                                Image(systemName: "play.rectangle")
                            }
                            .accessibilityLabel("Watch video")
                        }
                        #endif
                    }
                }
            }
            .sheet(isPresented: $isPresentingIngredients) {
                IngredientQuickView(
                    recipe: recipe,
                    servingMultiplier: $servingMultiplier,
                    checkedIngredientIDs: $checkedIngredientIDs
                )
            }
            .sheet(isPresented: $isPresentingTimers) {
                CookingTimersView(manager: timerManager)
            }
            #if os(iOS)
            .sheet(isPresented: $isPresentingVideos) {
                CookingModeVideoSheet(videoURLs: recipe.videoURLs)
            }
            #endif
        }
        #if os(iOS)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = keepsScreenAwake }
        .onChange(of: keepsScreenAwake) { _, newValue in
            UIApplication.shared.isIdleTimerDisabled = newValue
        }
        #endif
        .onDisappear {
            #if os(iOS)
            UIApplication.shared.isIdleTimerDisabled = false
            #endif
            timerManager.stop()
        }
        .onChange(of: hasStartedCooking) { _, started in
            if started { persistSession() }
        }
        .onChange(of: currentStepIndex) { _, _ in
            if hasStartedCooking { persistSession() }
            currentBackgroundImageName = CookingModeBackgroundCatalog.randomName(excluding: currentBackgroundImageName)
        }
    }

    /// So Home's "Continue Cooking" hero card can resume exactly where the
    /// user left off, even after the app relaunches.
    private func persistSession() {
        guard !flattenedSteps.isEmpty else { return }
        cookingSessionState.update(
            recipeID: recipe.id,
            ownerID: accountState.currentOwnerID,
            recipeTitle: recipe.title,
            currentStepIndex: currentStepIndex,
            totalSteps: flattenedSteps.count
        )
    }

    /// "Done" only clears the saved bookmark when the user has actually
    /// reached the last step — a genuine "I finished this recipe" signal.
    /// Tapping Done from an earlier step is just a pause (interrupted,
    /// switching to check something else, etc.), so the bookmark stays
    /// and Home's Continue Cooking card can still resume it later.
    private func finish() {
        if !flattenedSteps.isEmpty && currentStepIndex >= flattenedSteps.count - 1 {
            cookingSessionState.clear()
        }
        dismiss()
    }

    private var timersButtonAccessibilityLabel: String {
        timerManager.timers.isEmpty ? "Timers" : "Timers, \(timerManager.timers.count) active"
    }

    private var stepPager: some View {
        VStack(spacing: 0) {
            Text("Step \(currentStepIndex + 1) of \(flattenedSteps.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
                .accessibilityHidden(true)

            // Regular width (iPad, iPhone landscape on larger phones) gets
            // a side-by-side split; compact width (iPhone portrait, most
            // phones' default orientation) stacks the ingredient panel
            // below the pager instead, at a fixed height so it never
            // dominates the step text — "dynamic based on device and
            // orientation" per the original request.
            if horizontalSizeClass == .compact {
                stepTabView
                ingredientPanel
                    .frame(height: 180)
            } else {
                HStack(spacing: 0) {
                    stepTabView
                    Divider()
                    ingredientPanel
                        .frame(width: 340)
                }
            }

            controls
        }
        .background {
            Image(currentBackgroundImageName)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .accessibilityHidden(true)
        }
    }

    private var stepTabView: some View {
        TabView(selection: $currentStepIndex) {
            ForEach(Array(flattenedSteps.enumerated()), id: \.offset) { index, entry in
                stepPage(index: index, section: entry.section, step: entry.step)
                    .tag(index)
            }
        }
        #if os(iOS)
        .tabViewStyle(.page(indexDisplayMode: .always))
        #endif
    }

    /// Read-only, always-visible ingredient reference — "the recipe says
    /// 'add sugar,' but how much again?" — so nobody needs to leave the
    /// step they're on to check. The fuller interactive ingredient sheet
    /// (checkboxes, add-to-cart, scaling control) stays reachable via the
    /// toolbar button for when that's what's actually wanted.
    private var ingredientPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ingredients")
                    .font(.headline)
                IngredientReferenceListView(recipe: recipe, servingMultiplier: servingMultiplier)
            }
            .padding()
        }
        .background(.regularMaterial)
    }

    private var controls: some View {
        HStack {
            Button {
                move(to: max(0, currentStepIndex - 1))
            } label: {
                Label("Previous", systemImage: "chevron.left")
            }
            .disabled(currentStepIndex == 0)

            Spacer()

            Toggle(isOn: $keepsScreenAwake) {
                Label("Keep Screen Awake", systemImage: "sun.max")
            }
            .toggleStyle(.switch)
            .labelsHidden()
            .accessibilityLabel("Keep screen awake")

            Spacer()

            Button {
                move(to: min(flattenedSteps.count - 1, currentStepIndex + 1))
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .disabled(currentStepIndex == flattenedSteps.count - 1)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func move(to index: Int) {
        guard !reduceMotion else {
            currentStepIndex = index
            return
        }
        withAnimation { currentStepIndex = index }
    }

    private func stepPage(index: Int, section: String?, step: Step) -> some View {
        let isChecked = checkedStepIDs.contains(step.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let section, !section.isEmpty {
                    Text(section)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                Text(step.text)
                    .font(.title2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    toggleStepChecked(step.id)
                } label: {
                    Label(
                        isChecked ? "Marked Done" : "Mark Done",
                        systemImage: isChecked ? "checkmark.circle.fill" : "circle"
                    )
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            // Frosted-glass card so step text stays readable over a
            // photo background that can be busy in places — .regularMaterial
            // is a translucent blur that picks up whatever color is
            // actually behind it and adapts to light/dark mode, so it
            // "mixes nicely" with any of the rotating backgrounds without
            // needing per-image tuning.
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
            .padding()
        }
        .potluckHiddenScrollBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(index + 1) of \(flattenedSteps.count): \(step.text)")
    }

    private func toggleStepChecked(_ id: UUID) {
        if checkedStepIDs.contains(id) {
            checkedStepIDs.remove(id)
        } else {
            checkedStepIDs.insert(id)
        }
    }
}

#if os(iOS)
/// A video, plus which-of-up-to-3 picker when there's more than one.
/// Playback only ever starts once the user has explicitly tapped "Watch
/// Video" to get here — never inline/automatic in the main step flow.
private struct CookingModeVideoSheet: View {
    let videoURLs: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex = 0
    /// Picked once per sheet presentation (a plain @State initial value
    /// only re-evaluates when this view's identity is freshly created,
    /// i.e. each time the sheet opens) — not re-rolled on every body
    /// re-render, which would otherwise flicker between designs. See
    /// CookingModeBackgroundCatalog.swift, shared with the step pager.
    @State private var backgroundImageName = CookingModeBackgroundCatalog.randomName(excluding: nil)

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if videoURLs.count > 1 {
                    Picker("Video", selection: $selectedIndex) {
                        ForEach(Array(videoURLs.indices), id: \.self) { index in
                            Text("Video \(index + 1)").tag(index)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }

                #if os(iOS)
                if let videoID = YouTubeURL.videoID(from: videoURLs[selectedIndex]) {
                    YouTubePlayerView(videoID: videoID)
                        .id(videoID)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .potluckCardShadow()
                        .padding(.horizontal)
                } else {
                    ContentUnavailableView(
                        "Couldn't Load Video",
                        systemImage: "exclamationmark.triangle",
                        description: Text("This link doesn't look like a valid YouTube video anymore.")
                    )
                }
                #else
                // YouTubeiOSPlayerHelper (a WKWebView-based embed) is iOS-only
                // — no tvOS build of the underlying package exists (see its
                // Package.swift), so this platform gets a plain "open
                // elsewhere" message instead of an embedded player.
                ContentUnavailableView(
                    "Video Not Available Here",
                    systemImage: "tv.slash",
                    description: Text("Watch this recipe's video on your iPhone or iPad — video playback isn't supported on this device.")
                )
                #endif

                Spacer()
            }
            .padding(.top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                Image(backgroundImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            }
            .navigationTitle("Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif

#Preview {
    let recipe = Recipe(ownerID: "preview", title: "Skillet Cornbread")
    let section = StepSection()
    section.steps = [
        Step(text: "Preheat the oven to 425°F with the skillet inside.", sortOrder: 0),
        Step(text: "Whisk dry ingredients, then stir in buttermilk and egg.", sortOrder: 1),
    ]
    recipe.stepSections = [section]
    return CookingModeView(recipe: recipe)
        .modelContainer(for: Recipe.self, inMemory: true)
        .environment(AccountState(authService: FakeAuthService()))
        .environment(CookingSessionState())
}
