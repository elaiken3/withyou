//
//  EditReminderSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/6/26.
//

import Foundation
import SwiftUI
import SwiftData

struct EditReminderSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let reminder: VerboseReminder

    /// The reminder's time had already passed when the sheet opened (for example, opened
    /// from a notification). Its time then only changes if the person picks a new one,
    /// so fixing a typo never quietly reschedules it.
    private let originalTimeHasPassed: Bool

    @State private var title: String
    @State private var startStep: String
    @State private var estimate: Int
    @State private var scheduledAt: Date
    @State private var pickNewTime: Bool
    @State private var saveFailed = false
    @State private var isBreakingDown = false

    init(reminder: VerboseReminder) {
        self.reminder = reminder
        let hasPassed = reminder.scheduledAt <= Date()
        self.originalTimeHasPassed = hasPassed
        _title = State(initialValue: reminder.title)
        _startStep = State(initialValue: reminder.startStep)
        _estimate = State(initialValue: reminder.estimateMinutes)
        _scheduledAt = State(
            initialValue: hasPassed
                ? ReminderStore.roundedUp(Date().addingTimeInterval(60 * 60))
                : reminder.scheduledAt
        )
        _pickNewTime = State(initialValue: !hasPassed)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title, axis: .vertical)
                        .listRowBackground(Color.appSurface)
                }

                Section("First step") {
                    TextField("A tiny first step", text: $startStep, axis: .vertical)
                        .listRowBackground(Color.appSurface)

                    breakDownRow
                }

                Section {
                    EstimateMinutesPicker(minutes: $estimate)
                        .listRowBackground(Color.appSurface)
                } header: {
                    Text("Time")
                } footer: {
                    Text("A rough guess is plenty.")
                }

                whenSection

                if saveFailed {
                    Section {
                        Text("That didn’t save. Try again in a moment.")
                            .font(.footnote)
                            .foregroundStyle(.appSecondaryText)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .tint(.appAccent)
    }

    @ViewBuilder
    private var whenSection: some View {
        Section("When") {
            if originalTimeHasPassed {
                Text("Was \(reminder.scheduledAt.friendlyDayTime)")
                    .foregroundStyle(.appSecondaryText)
                    .listRowBackground(Color.appSurface)

                Toggle("Pick a new time", isOn: $pickNewTime)
                    .listRowBackground(Color.appSurface)
            }

            if pickNewTime {
                DatePicker(
                    "Time",
                    selection: $scheduledAt,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .listRowBackground(Color.appSurface)
            }
        }
    }

    /// "Break it down": tapping a step fills in the first step (and a smaller estimate).
    /// Nothing is saved until Save.
    @ViewBuilder
    private var breakDownRow: some View {
        if isBreakingDown {
            BreakDownView(
                title: trimmedTitle,
                currentStep: startStep,
                onPick: { step, index in
                    let change = BreakDownChoice.change(picking: step, at: index, previousEstimate: estimate)
                    startStep = change.startStep
                    estimate = change.estimateMinutes
                    isBreakingDown = false
                },
                onClose: {
                    isBreakingDown = false
                }
            )
            .listRowBackground(Color.appSurface)
        } else {
            Button {
                Haptics.tap()
                isBreakingDown = true
            } label: {
                Label("Break it down", systemImage: "list.number")
            }
            .disabled(trimmedTitle.isEmpty)
            .accessibilityHint("Shows a few tiny steps to pick from")
            .listRowBackground(Color.appSurface)
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }

        reminder.title = trimmedTitle
        reminder.startStep = startStep.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.estimateMinutes = estimate

        if pickNewTime, scheduledAt != reminder.scheduledAt {
            reminder.scheduledAt = scheduledAt
            reminder.lastCheckedAt = nil // a new time starts fresh
        }

        do {
            // Saves and replaces the pending notification with the new words and time.
            try ReminderStore.saveEdits(reminder, in: context)
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            print("❌ Save failed (EditReminderSheet):", error)
            saveFailed = true
        }
    }
}
