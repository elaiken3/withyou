//
//  FocusReviewView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct FocusReviewView: View {
    @Environment(\.modelContext) private var context
    let session: FocusSession
    var onDone: () -> Void

    @Query private var dumpItems: [FocusDumpItem]
    private let parser = CaptureParser()

    init(session: FocusSession, onDone: @escaping () -> Void) {
        self.session = session
        self.onDone = onDone
        _dumpItems = Query(
            filter: #Predicate<FocusDumpItem> { $0.sessionId == session.id },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Nice work.").font(.largeTitle).bold()
                Text("Here’s what you offloaded.")
                    .foregroundStyle(.secondary)

                if dumpItems.isEmpty {
                    Text("Nothing to process. You’re done.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(dumpItems) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                Text(item.text).font(.headline)
                                HStack {
                                    Button("Schedule") { scheduleTomorrowMorning(item) }
                                        .buttonStyle(.borderedProminent)
                                    Button("Inbox") { sendToInbox(item) }
                                        .buttonStyle(.bordered)
                                    Button("Not needed") {
                                        context.delete(item); try? context.save()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                Button("Return to Today") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Wrap up")
        }
    }

    private func sendToInbox(_ item: FocusDumpItem) {
        let profile = ProfileStore.activeProfile(in: context)
        let parsed = parser.parse(item.text, profile: profile)

        let inbox = InboxItem(content: item.text, title: parsed.title, source: .app, startStep: parsed.startStep, estimateMinutes: parsed.estimateMinutes)
        context.insert(inbox)
        context.delete(item)
        try? context.save()
    }

    private func scheduleTomorrowMorning(_ item: FocusDumpItem) {
        let profile = ProfileStore.activeProfile(in: context)
        let parsed = parser.parse(item.text, profile: profile)

        let when = tomorrowMorning(profile: profile)
        let reminder = VerboseReminder(title: parsed.title, startStep: parsed.startStep, estimateMinutes: parsed.estimateMinutes, scheduledAt: when)

        context.insert(reminder)
        context.delete(item)
        try? context.save()

        Task {
            let body = "Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)\nTap “Help me start” if you’re stuck."
            try? await NotificationManager.shared.scheduleReminder(id: reminder.id, title: reminder.title, body: body, scheduledAt: reminder.scheduledAt)
        }
    }

    private func tomorrowMorning(profile: UserProfile?) -> Date {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = profile?.morningHour ?? 9
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? tomorrow
    }
}

