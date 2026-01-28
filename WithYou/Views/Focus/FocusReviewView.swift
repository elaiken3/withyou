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
        let id: UUID = session.id
        _dumpItems = Query(
            filter: #Predicate<FocusDumpItem> { item in
                item.sessionId == id
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Nice work.")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.appPrimaryText)

                    Text("Here’s what you offloaded.")
                        .foregroundStyle(.appSecondaryText)

                    if dumpItems.isEmpty {
                        Text("Nothing to process. You’re done.")
                            .foregroundStyle(.appSecondaryText)
                    } else {
                        List {
                            ForEach(dumpItems) { item in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(item.text)
                                        .font(.headline)
                                        .foregroundStyle(.appPrimaryText)

                                    HStack {
                                        Button("Schedule") {
                                            Haptics.tap()
                                            scheduleTomorrowMorning(item)
                                        }
                                        .buttonStyle(.borderedProminent)

                                        Button("Inbox") {
                                            Haptics.tap()
                                            sendToInbox(item)
                                        }
                                        .buttonStyle(.bordered)

                                        Button("Not needed") {
                                            Haptics.tap()
                                            context.delete(item)
                                            do {
                                                try context.save()
                                                Haptics.success()
                                            } catch {
                                                Haptics.error()
                                                print("❌ Save failed (reviewNotNeeded):", error)
                                            }
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                                .padding(.vertical, 6)
                                .listRowBackground(Color.appSurface)
                            }
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.appSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
                        )
                    }

                    Button("Return to Today") {
                        Haptics.tap()
                        CompletionStore.completeFromSession(session, in: context)
                        onDone()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .padding(.top, 8)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Wrap up")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.appAccent)
        }
    }

    private func sendToInbox(_ item: FocusDumpItem) {
        let profile = ProfileStore.activeProfile(in: context)
        let parsed = parser.parse(item.text, profile: profile)

        let inbox = InboxItem(
            content: item.text,
            title: parsed.title,
            source: .app,
            startStep: parsed.startStep,
            estimateMinutes: parsed.estimateMinutes
        )

        context.insert(inbox)
        context.delete(item)

        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (sendToInbox):", error)
        }
    }

    private func scheduleTomorrowMorning(_ item: FocusDumpItem) {
        let profile = ProfileStore.activeProfile(in: context)
        let parsed = parser.parse(item.text, profile: profile)

        let when = tomorrowMorning(profile: profile)
        let reminder = VerboseReminder(
            title: parsed.title,
            startStep: parsed.startStep,
            estimateMinutes: parsed.estimateMinutes,
            scheduledAt: when
        )

        context.insert(reminder)
        context.delete(item)

        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (scheduleTomorrowMorning):", error)
            return
        }

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

    private func tomorrowMorning(profile: UserProfile?) -> Date {
        let now = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = profile?.morningHour ?? 9
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? tomorrow
    }
}
