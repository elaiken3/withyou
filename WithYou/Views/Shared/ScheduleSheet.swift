//
//  ScheduleSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftUI
import SwiftData

/// Picks a time for something. A few quick picks cover most cases; the calendar is there
/// for everything else. Calls `onPick` with the chosen time and closes itself.
struct ScheduleSheetV2: View {
    let title: String
    let startStep: String
    let estimate: Int
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var date: Date
    @State private var quickPicks: [ScheduleQuickPick] = []

    /// Grows with Dynamic Type, so the chips drop to one column at large text sizes.
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 150

    init(title: String, startStep: String, estimate: Int, onPick: @escaping (Date) -> Void) {
        self.title = title
        self.startStep = startStep
        self.estimate = estimate
        self.onPick = onPick
        // Default: about an hour from now, on a 5-minute mark.
        _date = State(initialValue: ReminderStore.roundedUp(Date().addingTimeInterval(60 * 60)))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard

                        if !quickPicks.isEmpty {
                            quickPickSection
                        }

                        calendarCard

                        selectionSummary

                        scheduleButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .tint(.appAccent)
            .onAppear {
                if quickPicks.isEmpty {
                    let picks = makeQuickPicks(now: Date())
                    quickPicks = picks
                    // Start on "In 1 hour" so the default is visibly one of the quick picks.
                    if let first = picks.first {
                        date = first.date
                    }
                }
            }
        }
        .presentationBackground(Color.appBackground)
    }

    // MARK: - Sections

    private var trimmedStep: String {
        startStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !trimmedStep.isEmpty {
                Text("Start: \(trimmedStep) (\(estimate) min)")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var quickPickSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Quick picks")

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: chipMinWidth), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(quickPicks) { pick in
                    QuickPickChip(pick: pick, isSelected: isSelected(pick)) {
                        Haptics.tap()
                        date = pick.date
                    }
                }
            }
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Or choose a time")

            DatePicker(
                "When",
                selection: $date,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.graphical)
            .labelsHidden()
        }
        .cardStyle()
    }

    private var selectionSummary: some View {
        Text(selectionText)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.appPrimaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
            .accessibilityLabel("Selected: \(selectionText)")
    }

    private var scheduleButton: some View {
        Button {
            Haptics.tap()
            // If the chosen minute slipped into the past while the sheet was open,
            // use the next few minutes rather than a time that can never notify.
            let now = Date()
            let when = date > now ? date : ReminderStore.roundedUp(now.addingTimeInterval(5 * 60))
            onPick(when)
            dismiss()
        } label: {
            Text("Schedule")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Helpers

    /// "Tomorrow at 9:00 AM", "Today at 7:00 PM", "Mar 12 at 9:00 AM".
    private var selectionText: String {
        let text = date.friendlyDayTime
        guard let first = text.first else { return text }
        return String(first).uppercased() + String(text.dropFirst())
    }

    private func isSelected(_ pick: ScheduleQuickPick) -> Bool {
        abs(date.timeIntervalSince(pick.date)) < 30
    }

    private func makeQuickPicks(now: Date) -> [ScheduleQuickPick] {
        let profile = ProfileStore.activeProfile(in: context)
        let calendar = Calendar.current
        var picks: [ScheduleQuickPick] = []

        let inAnHour = ReminderStore.roundedUp(now.addingTimeInterval(60 * 60))
        picks.append(ScheduleQuickPick(id: "hour", label: "In 1 hour", detail: inAnHour.timeText, date: inAnHour))

        // Only while the profile's evening hour is still ahead.
        if let evening = ReminderStore.thisEvening(profile: profile, now: now) {
            picks.append(ScheduleQuickPick(id: "evening", label: "This evening", detail: evening.timeText, date: evening))
        }

        let morning = ReminderStore.nextMorning(profile: profile, after: now)
        picks.append(ScheduleQuickPick(id: "morning", label: "Tomorrow morning", detail: morning.timeText, date: morning))

        // Next Saturday morning, skipped on the weekend itself (weekday 1 = Sunday, 7 = Saturday)
        // and on Fridays, when it would be the same as "Tomorrow morning".
        let weekday = calendar.component(.weekday, from: now)
        if weekday != 1, weekday != 7,
           let saturday = calendar.nextDate(
               after: now,
               matching: DateComponents(hour: profile?.morningHour ?? 9, minute: 0, weekday: 7),
               matchingPolicy: .nextTime
           ),
           !calendar.isDate(saturday, inSameDayAs: morning) {
            picks.append(
                ScheduleQuickPick(
                    id: "weekend",
                    label: "This weekend",
                    detail: saturday.formatted(.dateTime.weekday(.abbreviated).hour().minute()),
                    date: saturday
                )
            )
        }

        return picks
    }
}

// MARK: - Quick picks

private struct ScheduleQuickPick: Identifiable {
    let id: String
    let label: String
    let detail: String
    let date: Date
}

private struct QuickPickChip: View {
    let pick: ScheduleQuickPick
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(pick.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appPrimaryText)

                Text(pick.detail)
                    .font(.caption)
                    .foregroundStyle(.appSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.appAccent.opacity(0.16) : Color.appSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.appAccent : Color.appHairline.opacity(0.15),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
