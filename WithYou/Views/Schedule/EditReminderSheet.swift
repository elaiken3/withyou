//
//  EditReminderSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/6/26.
//

import SwiftUI
import SwiftData

struct EditReminderSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let reminder: VerboseReminder

    @State private var title: String
    @State private var startStep: String
    @State private var estimate: Int
    @State private var scheduledAt: Date

    init(reminder: VerboseReminder) {
        self.reminder = reminder
        _title = State(initialValue: reminder.title)
        _startStep = State(initialValue: reminder.startStep)
        _estimate = State(initialValue: reminder.estimateMinutes)
        _scheduledAt = State(initialValue: reminder.scheduledAt)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                }

                Section("First step") {
                    TextField("Start step", text: $startStep, axis: .vertical)
                }

                Section("Estimate") {
                    Stepper("\(estimate) min", value: $estimate, in: 1...120)
                }

                Section("When") {
                    DatePicker("Scheduled", selection: $scheduledAt, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Edit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.startStep = startStep.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.estimateMinutes = estimate
        reminder.scheduledAt = scheduledAt

        do {
            try context.save()
        } catch {
            print("❌ Save failed (EditReminderSheet):", error)
            return
        }

        Task {
            let body =
            """
            Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)
            Tap “Help me start” if you’re stuck.
            """

            try? await NotificationManager.shared.scheduleReminder(
                id: reminder.id,
                title: reminder.title,
                body: body,
                scheduledAt: reminder.scheduledAt
            )
        }

        dismiss()
    }
}
