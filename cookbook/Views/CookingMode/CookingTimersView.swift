//
//  CookingTimersView.swift
//  cookbook
//

import SwiftUI

struct CookingTimersView: View {
    let manager: CookingTimerManager
    @Environment(\.dismiss) private var dismiss
    @State private var newTimerName = ""
    @State private var newTimerMinutes = 5

    var body: some View {
        NavigationStack {
            List {
                Section("New Timer") {
                    if manager.canAddTimer {
                        TextField("Name (e.g. Rice)", text: $newTimerName)
                        PotluckStepper(value: $newTimerMinutes, range: 1...180, step: 1) {
                            Text("Duration: \(newTimerMinutes) min")
                        }
                        Button("Start Timer") {
                            manager.addTimer(name: newTimerName, totalSeconds: newTimerMinutes * 60)
                            newTimerName = ""
                        }
                    } else {
                        Text("You can have up to \(CookingTimerManager.maxConcurrentTimers) timers running at once. Remove one to start another.")
                            .foregroundStyle(.secondary)
                    }
                }

                if !manager.timers.isEmpty {
                    Section("Active Timers") {
                        ForEach(manager.timers) { timer in
                            timerRow(timer)
                        }
                    }
                }
            }
            .navigationTitle("Timers")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func timerRow(_ timer: CookingTimer) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(timer.name)
                    .font(.headline)
                Text(timer.isCompleted ? "Done" : timer.formattedRemaining)
                    .font(.title3.monospacedDigit())
                    .foregroundStyle(timer.isCompleted ? .green : .primary)
            }
            Spacer()
            if !timer.isCompleted {
                Button {
                    manager.toggleRunning(timer.id)
                } label: {
                    Image(systemName: timer.isRunning ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .accessibilityLabel(timer.isRunning ? "Pause \(timer.name)" : "Resume \(timer.name)")
            }
            Button(role: .destructive) {
                manager.remove(timer.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
            }
            .accessibilityLabel("Remove \(timer.name) timer")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(timer.name), \(timer.isCompleted ? "done" : "\(timer.formattedRemaining) remaining")")
    }
}
