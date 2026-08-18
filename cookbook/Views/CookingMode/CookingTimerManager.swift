//
//  CookingTimerManager.swift
//  cookbook
//
//  Session-only state for cooking mode's timers — nothing here is
//  persisted across app launches; it exists only while cooking mode is on
//  screen. What DOES survive the app backgrounding: each timer tracks an
//  absolute `endDate` rather than a decrementing counter, so the displayed
//  time is always derived from the wall clock (correct the instant the
//  view re-renders after returning to foreground, no resync plumbing
//  needed) — and, on iOS/macOS, a local notification is scheduled per
//  running timer so completion is signaled even while fully backgrounded,
//  which a plain in-app Timer can never do on its own (it stops firing the
//  moment the app is suspended).
//

import AudioToolbox
import Foundation
import Observation
import UIKit
#if os(iOS) || os(macOS)
import UserNotifications
#endif

struct CookingTimer: Identifiable {
    let id = UUID()
    var name: String
    var totalSeconds: Int
    /// When running, remaining time is always derived from this — never
    /// accumulated/decremented, so backgrounding can't desync it from
    /// reality. Meaningless while paused (see `pausedRemainingSeconds`).
    var endDate: Date
    /// Non-nil only while paused — `remainingSeconds` reads from this
    /// instead of `endDate` in that state; resuming clears it and computes
    /// a fresh `endDate`.
    var pausedRemainingSeconds: Int?
    var isRunning: Bool = true
    var isCompleted: Bool = false

    var remainingSeconds: Int {
        if let pausedRemainingSeconds { return pausedRemainingSeconds }
        return max(0, Int(endDate.timeIntervalSinceNow.rounded(.up)))
    }

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
            endDate: Date().addingTimeInterval(TimeInterval(totalSeconds))
        )
        timers.append(timer)
        scheduleNotification(for: timer)
    }

    func toggleRunning(_ id: CookingTimer.ID) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        if timers[index].isRunning {
            // Pausing: freeze the current remaining time — endDate stops
            // meaning anything until resumed.
            timers[index].pausedRemainingSeconds = timers[index].remainingSeconds
            timers[index].isRunning = false
            cancelNotification(for: timers[index])
        } else {
            // Resuming: start a fresh endDate from whatever was frozen.
            let remaining = timers[index].pausedRemainingSeconds ?? 0
            timers[index].endDate = Date().addingTimeInterval(TimeInterval(remaining))
            timers[index].pausedRemainingSeconds = nil
            timers[index].isRunning = true
            scheduleNotification(for: timers[index])
        }
    }

    func remove(_ id: CookingTimer.ID) {
        if let timer = timers.first(where: { $0.id == id }) {
            cancelNotification(for: timer)
        }
        timers.removeAll { $0.id == id }
    }

    private func tick() {
        for index in timers.indices {
            guard timers[index].isRunning, timers[index].remainingSeconds > 0 else { continue }
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

    #if os(iOS) || os(macOS)
    /// Requested contextually, the first time a user ever adds a timer —
    /// not at launch, not blindly. A denial just means no background
    /// notification; the in-app sound/haptic/VoiceOver signal above still
    /// covers the foreground case regardless.
    private func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private func scheduleNotification(for timer: CookingTimer) {
        Task {
            await requestNotificationAuthorizationIfNeeded()
            let content = UNMutableNotificationContent()
            content.title = "\(timer.name) timer is done"
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, TimeInterval(timer.remainingSeconds)), repeats: false
            )
            let request = UNNotificationRequest(identifier: timer.id.uuidString, content: content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func cancelNotification(for timer: CookingTimer) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [timer.id.uuidString])
    }
    #else
    private func scheduleNotification(for timer: CookingTimer) {}
    private func cancelNotification(for timer: CookingTimer) {}
    #endif
}
