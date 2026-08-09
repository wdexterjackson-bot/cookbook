//
//  CookingModeActiveTimersBanner.swift
//  cookbook
//
//  Always-visible on every Cooking Mode page (prep review + every step
//  page, via CookingModeView's shared .safeAreaInset) — not just reachable
//  through the timers sheet — so a running timer (up to 3 at once, see
//  CookingTimerManager.maxConcurrentTimers) stays in view no matter which
//  step someone's on. Each row shows the timer's name and remaining time
//  (both needed once more than one timer is running) and its own dismiss
//  button — closing one here calls the same CookingTimerManager.remove(_:)
//  the full timers sheet uses, no separate state to keep in sync.
//

import SwiftUI

struct CookingModeActiveTimersBanner: View {
    let manager: CookingTimerManager

    var body: some View {
        if !manager.timers.isEmpty {
            VStack(spacing: 6) {
                ForEach(manager.timers) { timer in
                    timerRow(timer)
                }
            }
            .padding(10)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: PotluckMetrics.cardCornerRadius))
            .padding(.horizontal)
            .padding(.top, 6)
        }
    }

    private func timerRow(_ timer: CookingTimer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: timer.isCompleted ? "checkmark.circle.fill" : "timer")
                .foregroundStyle(timer.isCompleted ? Color.potluckSage : .primary)
            Text(timer.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Spacer()
            Text(timer.isCompleted ? "Done" : timer.formattedRemaining)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(timer.isCompleted ? Color.potluckSage : .secondary)
            Button {
                manager.remove(timer.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss \(timer.name) timer")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timer.name), \(timer.isCompleted ? "done" : "\(timer.formattedRemaining) remaining")")
    }
}
