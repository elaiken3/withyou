//
//  ScheduleView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/29/25.
//

import SwiftUI
import SwiftData

struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VerboseReminder.scheduledAt, order: .forward) private var reminders: [VerboseReminder]

    @State private var editingReminder: VerboseReminder?
    @State private var reminderPendingDeletion: VerboseReminder?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if groupedReminders.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(groupedReminders, id: \.dayKey) { section in
                            Section(section.headerTitle) {
                                ForEach(section.items) { reminder in
                                    ScheduleRow(reminder: reminder)
                                        .contentShape(Rectangle()) // tap anywhere
                                        .onTapGesture {
                                            Haptics.tap()
                                            editingReminder = reminder
                                        }
                                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                            Button {
                                                Haptics.tap()
                                                editingReminder = reminder
                                            } label: {
                                                Label("Reschedule", systemImage: "calendar")
                                            }

                                            Button(role: .destructive) {
                                                Haptics.tap()
                                                reminderPendingDeletion = reminder
                                            } label: {
                                                Label("Not needed", systemImage: "trash")
                                            }
                                            
                                            Button {
                                                Haptics.tap()
                                                CompletionStore.completeReminder(reminder, in: context)
                                            } label: {
                                                Label("Completed", systemImage: "checkmark.circle")
                                            }
                                            .tint(.green)
                                        }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.appBackground)
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)

            // Edit / reschedule sheet (uses your existing file)
            .sheet(item: $editingReminder) { reminder in
                EditReminderSheet(reminder: reminder)
                    .presentationBackground(Color.appBackground)
            }

            // Not needed confirmation
            .confirmationDialog(
                "Let this go?",
                isPresented: isConfirmingDeletion,
                presenting: reminderPendingDeletion
            ) { reminder in
                Button("Let go", role: .destructive) {
                    delete(reminder)
                    reminderPendingDeletion = nil
                }
                Button("Keep", role: .cancel) {
                    reminderPendingDeletion = nil
                }
            } message: { _ in
                Text("You don’t have to do everything.")
            }
            .tint(.appAccent)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing scheduled yet.")
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("When you schedule something, it’ll show up here — date and time included.")
                .foregroundStyle(.appSecondaryText)
        }
        .padding()
    }
    
    private var isConfirmingDeletion: Binding<Bool> {
        Binding(
            get: { reminderPendingDeletion != nil },
            set: { newValue in
                if !newValue { reminderPendingDeletion = nil }
            }
        )
    }

    // MARK: - Grouping

    private struct DaySection {
        let dayKey: Date
        let headerTitle: String
        let items: [VerboseReminder]
    }

    private var groupedReminders: [DaySection] {
        let cal = Calendar.current
        let now = Date()

        let upcoming = reminders
            .filter { !$0.isDone } // keep it simple; remove if you want to show done
            .sorted { $0.scheduledAt < $1.scheduledAt }

        let grouped = Dictionary(grouping: upcoming) { r in
            cal.startOfDay(for: r.scheduledAt)
        }

        let dayKeys = grouped.keys.sorted()

        return dayKeys.map { day in
            let header: String
            if cal.isDateInToday(day) {
                header = "Today"
            } else if cal.isDateInTomorrow(day) {
                header = "Tomorrow"
            } else if cal.isDate(day, equalTo: now, toGranularity: .year) {
                let f = DateFormatter()
                f.dateFormat = "EEEE, MMM d" // Tue, Jan 6
                header = f.string(from: day)
            } else {
                let f = DateFormatter()
                f.dateFormat = "EEEE, MMM d, yyyy"
                header = f.string(from: day)
            }

            let items = (grouped[day] ?? []).sorted { $0.scheduledAt < $1.scheduledAt }
            return DaySection(dayKey: day, headerTitle: header, items: items)
        }
    }

    // MARK: - Actions

    private func delete(_ reminder: VerboseReminder) {
        // Cancel pending notif (if you have this helper)
        NotificationManager.shared.cancelReminder(id: reminder.id)

        context.delete(reminder)
        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (delete reminder):", error)
        }
    }
}

// MARK: - Row UI

private struct ScheduleRow: View {
    let reminder: VerboseReminder

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(reminder.title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)")
                .foregroundStyle(.appSecondaryText)
                .lineLimit(2)

            Text(timeString(reminder.scheduledAt))
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)
        }
        .padding(.vertical, 6)
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date).lowercased()
    }
}
