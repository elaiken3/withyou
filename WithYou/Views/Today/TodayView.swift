//
//  TodayView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VerboseReminder.scheduledAt, order: .forward) private var reminders: [VerboseReminder]

    @State private var showFocus = false
    @State private var showRefocus = false
    @State private var toast: String?

    private var todayItems: [VerboseReminder] {
        reminders.filter { !$0.isDone }.prefix(3).map { $0 }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Button {
                    showFocus = true
                } label: {
                    VStack(alignment: .leading) {
                        Text("Start Focus Session").font(.headline)
                        Text("Brain dump + short timeline (25–60 min).")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)
                .sheet(isPresented: $showFocus) { FocusSessionFlowView() }

                List {
                    if todayItems.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nothing in Today yet").font(.headline)
                            Text("Capture something or pull from Inbox when you’re ready.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                    }

                    ForEach(todayItems) { r in
                        TodayRow(reminder: r)
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showRefocus = true } label: {
                        Image(systemName: "wind")
                    }
                }
            }
            .sheet(isPresented: $showRefocus) { RefocusView() }
            .onReceive(NotificationCenter.default.publisher(for: .reminderActionReceived)) { note in
                handleNotificationAction(note)
            }
            .overlay(alignment: .bottom) {
                if let t = toast {
                    Text(t)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding()
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { toast = nil }
                        }
                }
            }
        }
    }

    private func handleNotificationAction(_ note: Notification) {
        guard
            let info = note.userInfo,
            let id = info["reminderId"] as? UUID,
            let actionId = info["actionId"] as? String,
            let r = reminders.first(where: { $0.id == id })
        else { return }

        switch actionId {
        case ReminderAction.started.rawValue:
            r.isStarted = true
            toast = "Started: \(r.title)"
        case ReminderAction.helpMeStart.rawValue:
            toast = "Start: \(r.startStep)"
        case ReminderAction.snooze10.rawValue:
            r.scheduledAt = Date().addingTimeInterval(10 * 60)
            reschedule(r)
            toast = "Snoozed 10 min"
        case ReminderAction.reschedTomorrowMorning.rawValue:
            r.scheduledAt = tomorrowMorning()
            reschedule(r)
            toast = "Moved to tomorrow morning"
        default:
            break
        }

        try? context.save()
    }

    private func reschedule(_ r: VerboseReminder) {
        Task {
            let body = "Start: \(r.startStep) (\(r.estimateMinutes) min)\nTap “Help me start” if you’re stuck."
            try? await NotificationManager.shared.scheduleReminder(id: r.id, title: r.title, body: body, scheduledAt: r.scheduledAt)
        }
    }

    private func tomorrowMorning() -> Date {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = (ProfileStore.activeProfile(in: context)?.morningHour ?? 9)
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? tomorrow
    }
}

private struct TodayRow: View {
    @Environment(\.modelContext) private var context
    let reminder: VerboseReminder
    @State private var showHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(reminder.title).font(.headline)
            Text("Start: \(reminder.startStep)")
                .foregroundStyle(.secondary)
            Text("~\(reminder.estimateMinutes) min • \(reminder.scheduledAt.formatted(date: .omitted, time: .shortened))")
                .foregroundStyle(.secondary)

            HStack {
                Button("Started") {
                    reminder.isStarted = true
                    try? context.save()
                }
                .buttonStyle(.borderedProminent)

                Button("Help me start") { showHelp = true }
                    .buttonStyle(.bordered)

                Button("Done") {
                    reminder.isDone = true
                    try? context.save()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showHelp) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Help me start").font(.title2).bold()
                Text("Do this first:").foregroundStyle(.secondary)
                Text(reminder.startStep).font(.headline)

                Button("Make it smaller (2 min)") {
                    reminder.startStep = "Open the first app → do one tiny step"
                    reminder.estimateMinutes = 2
                    try? context.save()
                }
                .buttonStyle(.borderedProminent)

                Button("Close") { showHelp = false }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }
}
