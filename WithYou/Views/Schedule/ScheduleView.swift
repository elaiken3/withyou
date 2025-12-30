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

    @Query(sort: \VerboseReminder.scheduledAt, order: .forward)
    private var reminders: [VerboseReminder]

    var body: some View {
        NavigationStack {
            List {
                if upcoming.isEmpty {
                    Section {
                        Text("Nothing scheduled yet.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(groupedDays, id: \.day) { group in
                        Section(header: Text(sectionTitle(for: group.day))) {
                            ForEach(group.items) { r in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(r.title)
                                        .font(.headline)

                                    if !r.startStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Start: \(r.startStep)")
                                            .foregroundStyle(.secondary)
                                    }

                                    // Shows both date + time in a nice localized format
                                    Text(r.scheduledAt, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                            .onDelete { offsets in
                                delete(offsets, in: group.items)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Schedule")
        }
    }

    // MARK: - Data

    private var upcoming: [VerboseReminder] {
        let now = Date()
        return reminders.filter { $0.scheduledAt >= now }
    }

    private struct DayGroup {
        let day: Date            // startOfDay
        let items: [VerboseReminder]
    }

    private var groupedDays: [DayGroup] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: upcoming) { cal.startOfDay(for: $0.scheduledAt) }

        return grouped
            .map { DayGroup(day: $0.key, items: $0.value.sorted(by: { $0.scheduledAt < $1.scheduledAt })) }
            .sorted(by: { $0.day < $1.day })
    }

    // MARK: - UI helpers

    private func sectionTitle(for day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInTomorrow(day) { return "Tomorrow" }

        return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    // MARK: - Actions

    private func delete(_ offsets: IndexSet, in items: [VerboseReminder]) {
        for idx in offsets {
            let r = items[idx]
            context.delete(r)

            // Optional: if you later add cancellation support:
            // NotificationManager.shared.cancelReminder(id: r.id)
        }
        try? context.save()
    }
}
