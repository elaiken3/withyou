//
//  ScheduleView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/29/25.
//

import Foundation
import SwiftUI
import SwiftData

/// What's coming up. Only reminders that are still ahead are listed: past ones come back
/// one at a time on Today ("Still relevant?"), so they never pile up here as a backlog.
struct ScheduleView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(
        filter: #Predicate<VerboseReminder> { reminder in
            reminder.isDone == false
        },
        sort: \VerboseReminder.scheduledAt,
        order: .forward
    ) private var openReminders: [VerboseReminder]

    @State private var now = Date()
    @State private var editingReminder: VerboseReminder?
    @State private var reschedulingReminder: VerboseReminder?
    @State private var toast: Toast?

    var body: some View {
        let sections = daySections

        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if sections.isEmpty {
                    emptyState
                } else {
                    list(sections)
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.appAccent)
            .toast($toast)
            .sheet(item: $editingReminder) { reminder in
                EditReminderSheet(reminder: reminder)
                    .presentationBackground(Color.appBackground)
            }
            .sheet(item: $reschedulingReminder) { reminder in
                ScheduleSheetV2(
                    title: reminder.title,
                    startStep: reminder.startStep,
                    estimate: reminder.estimateMinutes
                ) { date in
                    reschedule(reminder, to: date)
                }
                .presentationBackground(Color.appBackground)
            }
            .task {
                // Keeps "still ahead" accurate while the screen stays open.
                while !Task.isCancelled {
                    now = Date()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    now = Date()
                }
            }
        }
    }

    // MARK: - List

    private func list(_ sections: [DaySection]) -> some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.reminders) { reminder in
                        row(for: reminder)
                    }
                } header: {
                    Text(section.day.dayHeaderText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.appSecondaryText)
                        .textCase(nil)
                        .accessibilityAddTraits(.isHeader)
                }
            }

            Section {
            } footer: {
                Text("Past reminders come back one at a time on Today.")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    private func row(for reminder: VerboseReminder) -> some View {
        Button {
            Haptics.tap()
            editingReminder = reminder
        } label: {
            ScheduleRow(reminder: reminder)
        }
        .listRowBackground(Color.appSurface)
        .accessibilityHint("Opens it to edit")
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                Haptics.tap()
                reschedulingReminder = reminder
            } label: {
                Label("Reschedule", systemImage: "calendar")
            }
            .tint(.appAccent)

            Button {
                complete(reminder)
            } label: {
                Label("Done", systemImage: "checkmark")
            }
            .tint(.appAccent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                letGo(reminder)
            } label: {
                Label("Let go", systemImage: "leaf")
            }
            .tint(.appSecondaryText)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.largeTitle)
                    .foregroundStyle(.appSecondaryText)
                    .accessibilityHidden(true)

                Text("Nothing coming up.")
                    .font(.headline)
                    .foregroundStyle(.appPrimaryText)

                Text("When you give something a time, it waits here quietly.")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if hasPastReminders {
                    Text("Past reminders come back one at a time on Today.")
                        .font(.footnote)
                        .foregroundStyle(.appSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 32)
            .accessibilityElement(children: .combine)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Grouping

    private struct DaySection: Identifiable {
        let day: Date
        let reminders: [VerboseReminder]

        var id: Date { day }
    }

    private var upcoming: [VerboseReminder] {
        openReminders.filter { $0.scheduledAt > now }
    }

    private var hasPastReminders: Bool {
        openReminders.contains { $0.scheduledAt <= now }
    }

    private var daySections: [DaySection] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcoming) { reminder in
            calendar.startOfDay(for: reminder.scheduledAt)
        }

        return grouped.keys.sorted().map { day in
            let reminders = (grouped[day] ?? []).sorted { $0.scheduledAt < $1.scheduledAt }
            return DaySection(day: day, reminders: reminders)
        }
    }

    // MARK: - Actions

    private func complete(_ reminder: VerboseReminder) {
        CompletionStore.completeReminder(reminder, in: context)
        Haptics.success()
        toast = Toast(text: "Nice. That counted.")
    }

    private func reschedule(_ reminder: VerboseReminder, to date: Date) {
        do {
            try ReminderStore.reschedule(reminder, to: date, in: context)
            Haptics.success()
            toast = Toast(text: "Moved to \(date.friendlyDayTime).")
        } catch {
            Haptics.error()
            print("❌ Save failed (reschedule):", error)
            toast = Toast(text: "Couldn’t move it just now.")
        }
    }

    /// Lets the reminder go right away (and cancels its notification), with Undo.
    private func letGo(_ reminder: VerboseReminder) {
        Haptics.tap()

        let title = reminder.title
        let why = reminder.why
        let startStep = reminder.startStep
        let estimate = reminder.estimateMinutes
        let scheduledAt = reminder.scheduledAt
        let createdAt = reminder.createdAt
        let isStarted = reminder.isStarted

        do {
            try ReminderStore.letGo(reminder, in: context)
        } catch {
            Haptics.error()
            print("❌ Save failed (let go reminder):", error)
            return
        }

        toast = Toast(text: "Let go.", actionTitle: "Undo", action: {
            let restored = VerboseReminder(
                title: title,
                why: why,
                startStep: startStep,
                estimateMinutes: estimate,
                scheduledAt: scheduledAt,
                createdAt: createdAt,
                isStarted: isStarted
            )
            context.insert(restored)
            do {
                try context.save()
                ReminderStore.refreshNotification(for: restored)
            } catch {
                print("❌ Save failed (undo let go reminder):", error)
            }
        })
    }
}

// MARK: - Row UI

private struct ScheduleRow: View {
    let reminder: VerboseReminder

    private var startStep: String {
        reminder.startStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminder.scheduledAt.timeText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.appAccent)

            Text(reminder.title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !startStep.isEmpty {
                Text("Start: \(startStep) (\(reminder.estimateMinutes) min)")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
