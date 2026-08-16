//
//  CookingTimerManager.swift
//  cookbook
//
//  Session-only state for cooking mode's timers — nothing here is
//  persisted; it exists only while cooking mode is on screen.
//

import AudioToolbox
import Foundation
import Observation
import UIKit

struct CookingTimer: Identifiable {
    let id = UUID()
    var name: String
    var totalSeconds: Int
    var remainingSeconds: Int
    var isRunning: Bool = true
    var isCompleted: Bool = false

    var formattedRemaining: String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@MainActor
@Observable
final class CookingTimerManager {
    private(set) var timers: [CookingTimer] = []
    private var repeatingTimer: Timer?

    /// Up to 3 timers at once — enough for a real multi-burner/multi-dish
    /// cook without the always-visible on-page banner (CookingModeView)
    /// growing unbounded.
    static let maxConcurrentTimers = 3
    var canAddTimer: Bool { timers.count < Self.maxConcurrentTimers }

    init() {
        repeatingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// Call when the owning view disappears — an @Observable stored property
    /// can't be touched from `deinit` (which runs nonisolated), so cleanup
    /// happens explicitly instead of relying on deallocation.
    func stop() {
        repeatingTimer?.invalidate()
        repeatingTimer = nil
    }

    func addTimer(name: String, totalSeconds: Int) {
        guard canAddTimer else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let timer = CookingTimer(
            name: trimmedName.isEmpty ? "Timer \(timers.count + 1)" : trimmedName,
            totalSeconds: totalSeconds,
            remainingSeconds: totalSeconds
        )
        timers.append(timer)
    }

    func toggleRunning(_ id: CookingTimer.ID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].isRunning.toggle()
    }

    func remove(_ id: CookingTimer.ID) {
        timers.removeAll { $0.id == id }
    }

    private func tick() {
        for index in timers.indices {
            guard timers[index].isRunning, timers[index].remainingSeconds > 0 else { continue }
            timers[index].remainingSeconds -= 1
            if timers[index].remainingSeconds == 0 {
                timers[index].isRunning = false
                timers[index].isCompleted = true
                announceCompletion(of: timers[index])
            }
        }
    }

    /// Pairs the "Done" visual state change above with the audible, haptic,
    /// and VoiceOver signals PRD A11Y-004 requires for Cooking Mode timers —
    /// hands are often busy or dirty while cooking, and a purely visual
    /// label change in a sheet the user isn't looking at was easy to miss
    /// entirely (there was previously no signal at all on completion).
    private func announceCompletion(of timer: CookingTimer) {
        AudioServicesPlaySystemSound(1005)
        // No haptic engine exposed to UIKit on tvOS (Siri Remote or not).
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
        UIAccessibility.post(notification: .announcement, argument: "\(timer.name) timer is done")
    }
}
