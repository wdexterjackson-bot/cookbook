//
//  CookingTimerManager.swift
//  cookbook
//
//  Session-only state for cooking mode's timers — nothing here is
//  persisted; it exists only while cooking mode is on screen.
//

import Foundation
import Observation

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
            }
        }
    }
}
