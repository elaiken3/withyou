//
//  InboxView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \InboxItem.createdAt, order: .reverse) private var items: [InboxItem]

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inbox is empty").font(.headline)
                        Text("Captured thoughts land here when there’s no time yet.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }

                ForEach(items) { item in
                    InboxRow(item: item)
                }
                .onDelete { idx in
                    for i in idx { context.delete(items[i]) }
                    try? context.save()
                }
            }
            .navigationTitle("Inbox")
        }
    }
}

private struct InboxRow: View {
    @Environment(\.modelContext) private var context
    let item: InboxItem
    @State private var showSchedule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title).font(.headline)
            Text("Start: \(item.startStep) (\(item.estimateMinutes) min)")
                .foregroundStyle(.secondary)

            HStack {
                Button("Schedule") { showSchedule = true }
                    .buttonStyle(.borderedProminent)

                Button("Make smaller") {
                    item.startStep = "Open the first app → do one tiny step"
                    item.estimateMinutes = 2
                    try? context.save()
                }
                .buttonStyle(.bordered)

                Button("Not needed") {
                    context.delete(item)
                    try? context.save()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
        .sheet(isPresented: $showSchedule) {
            ScheduleSheet(title: item.title, startStep: item.startStep, estimate: item.estimateMinutes) { date in
                let reminder = VerboseReminder(
                    title: item.title,
                    startStep: item.startStep,
                    estimateMinutes: item.estimateMinutes,
                    scheduledAt: date
                )
                context.insert(reminder)
                context.delete(item)
                try? context.save()

                Task {
                    let body = "Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)\nTap “Help me start” if you’re stuck."
                    try? await NotificationManager.shared.scheduleReminder(
                        id: reminder.id,
                        title: reminder.title,
                        body: body,
                        scheduledAt: reminder.scheduledAt
                    )
                }
            }
        }
    }
}
