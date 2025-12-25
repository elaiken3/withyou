//
//  InboxDetailView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/25/25.
//

import SwiftUI
import SwiftData

struct InboxDetailView: View {
    @Environment(\.modelContext) private var context

    let item: InboxItem

    @State private var showSchedule = false
    @State private var isDeleting = false

    var body: some View {
        List {
            Section("Captured") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.headline)

                    Text(item.content)
                        .foregroundStyle(.secondary)

                    Text("Start: \(item.startStep) (\(item.estimateMinutes) min)")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Actions") {
                Button {
                    showSchedule = true
                } label: {
                    Label("Schedule", systemImage: "calendar.badge.plus")
                }

                Button {
                    makeSmaller()
                } label: {
                    Label("Make smaller (2 min)", systemImage: "scissors")
                }

                Button(role: .destructive) {
                    deleteItem()
                } label: {
                    Label("Not needed", systemImage: "trash")
                }
                .disabled(isDeleting)
            }
        }
        .navigationTitle("Inbox Item")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSchedule) {
            ScheduleSheet(
                title: item.title,
                startStep: item.startStep,
                estimate: item.estimateMinutes
            ) { date in
                schedule(date: date)
            }
        }
    }

    private func makeSmaller() {
        item.startStep = makeSmallerStep(for: item.title)
        item.estimateMinutes = 2

        do {
            try context.save()
        } catch {
            print("❌ Save failed (makeSmaller):", error)
        }
    }

    private func makeSmallerStep(for title: String) -> String {
        // Simple v1 heuristic. You can get smarter later.
        "Open what you need and do the smallest possible step for 2 minutes."
    }

    private func deleteItem() {
        isDeleting = true
        context.delete(item)

        do {
            try context.save()
        } catch {
            print("❌ Save failed (delete):", error)
        }

        isDeleting = false
    }

    private func schedule(date: Date) {
        let reminder = VerboseReminder(
            title: item.title,
            startStep: item.startStep,
            estimateMinutes: item.estimateMinutes,
            scheduledAt: date
        )

        context.insert(reminder)
        context.delete(item)

        do {
            try context.save()
        } catch {
            print("❌ Save failed (schedule):", error)
        }

        Task {
            let body =
            """
            Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)
            Tap “Help me start” if you’re stuck.
            """

            do {
                try await NotificationManager.shared.scheduleReminder(
                    id: reminder.id,
                    title: reminder.title,
                    body: body,
                    scheduledAt: reminder.scheduledAt
                )
            } catch {
                print("❌ Notification schedule failed:", error)
            }
        }
    }
}
