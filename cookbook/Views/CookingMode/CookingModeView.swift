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
    @Environment(AccountState.self) private var accountState
    @Environment(CookingSessionState.self) private var cookingSessionState

    @State private var currentStepIndex = 0
    @State private var checkedStepIDs: Set<UUID> = []
    @State private var checkedIngredientIDs: Set<UUID> = []
    @State private var servingMultiplier: Double = 1
    @State private var keepsScreenAwake = true
    @State private var isPresentingIngredients = false
    @State private var isPresentingTimers = false
    @State private var timerManager = CookingTimerManager()

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
                } else {
                    stepPager
                }
            }
            .background(Color.potluckCream)
            .navigationTitle(recipe.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
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
        .onAppear { persistSession() }
        .onChange(of: currentStepIndex) { _, _ in persistSession() }
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

            TabView(selection: $currentStepIndex) {
                ForEach(Array(flattenedSteps.enumerated()), id: \.offset) { index, entry in
                    stepPage(index: index, section: entry.section, step: entry.step)
                        .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif

            controls
        }
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
        }
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
