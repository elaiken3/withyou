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
    @Binding var selectedTab: AppTab

    init(selectedTab: Binding<AppTab> = .constant(.today)) {
            self._selectedTab = selectedTab
        }
    // Pull data we know exists in your models
    @Query(sort: \VerboseReminder.scheduledAt, order: .forward) private var reminders: [VerboseReminder]
    @Query(sort: \InboxItem.createdAt, order: .reverse) private var inboxItems: [InboxItem]
    @Query(sort: \FocusSession.createdAt, order: .reverse) private var sessions: [FocusSession]

    @State private var showRefocus = false
    @State private var showScheduleForInboxItem: InboxItem?
    @State private var toastMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // RIGHT NOW (one card)
                    Text("Right now")
                        .font(.headline)
                        .padding(.horizontal)

                    if let active = activeFocusSession {
                        TodayCard(
                            title: "You’re in a focus session",
                            subtitle: "Focusing on: \(active.focusTitle). Want to keep going?"
                        ) {
                            Button("Resume focus") {
                                selectedTab = .focus
                            }
                            .buttonStyle(.borderedProminent)

                            .buttonStyle(.borderedProminent)

                            Button("Refocus (30 sec)") { showRefocus = true }
                                .buttonStyle(.bordered)
                        }
                        .padding(.horizontal)

                    } else if let next = nextReminderToday {
                        TodayTaskCard(
                            title: next.title,
                            startStep: next.startStep,
                            estimateMinutes: next.estimateMinutes,
                            primaryButtonTitle: "Start a focus session",
                            secondaryButtonTitle: "Not now"
                        ) {
                            startFocusSession(title: next.title, startStep: next.startStep)
                        } secondaryAction: {
                            // Gentle: no punishment, no overdue
                            toast("No problem. It can wait.")
                        }
                        .padding(.horizontal)

                    } else if let tiny = nextTinyInboxItem {
                        TodayTaskCard(
                            title: tiny.title,
                            startStep: tiny.startStep,
                            estimateMinutes: tiny.estimateMinutes,
                            primaryButtonTitle: "Do the first step (2 min)",
                            secondaryButtonTitle: "Make it smaller"
                        ) {
                            // “Do the first step” = start a short focus session
                            startFocusSession(title: tiny.title, startStep: tiny.startStep)
                        } secondaryAction: {
                            makeInboxItemSmaller(tiny)
                        }
                        .padding(.horizontal)

                    } else {
                        TodayEmptyCard()
                            .padding(.horizontal)
                    }

                    // OPTIONAL SECTION
                    Text("If you have energy")
                        .font(.headline)
                        .padding(.horizontal)

                    if let suggestion = secondarySuggestionInboxItem {
                        SuggestionRow(
                            title: suggestion.title,
                            subtitle: "Start: \(suggestion.startStep) (\(suggestion.estimateMinutes) min)",
                            primaryTitle: "Schedule",
                            secondaryTitle: "Not needed"
                        ) {
                            showScheduleForInboxItem = suggestion
                        } secondary: {
                            deleteInboxItem(suggestion)
                        }
                        .padding(.horizontal)
                    } else {
                        Text("Nothing extra needed today.")
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                    }

                    // SUPPORT
                    Text("Reset")
                        .font(.headline)
                        .padding(.horizontal)

                    Button {
                        showRefocus = true
                    } label: {
                        HStack {
                            Image(systemName: "wind")
                            Text("Refocus (30 seconds)")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .padding(.horizontal)

                    // Gentle Inbox indicator (no guilt)
                    if !inboxItems.isEmpty {
                        Text("Inbox has \(inboxItems.count) item(s). You don’t need to clear it today.")
                            .foregroundStyle(.secondary)
                            .font(.footnote)
                            .padding(.horizontal)
                            .padding(.top, 4)
                    }
                }
                .padding(.vertical, 12)
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showRefocus) {
                RefocusSheet()
            }
            .sheet(item: $showScheduleForInboxItem) { item in
                ScheduleSheet(
                    title: item.title,
                    startStep: item.startStep,
                    estimate: item.estimateMinutes
                ) { date in
                    convertInboxItemToReminder(item, date: date)
                }
            }
            .overlay(alignment: .bottom) {
                if let toastMessage {
                    ToastView(text: toastMessage)
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onAppear {
                ProfileStore.ensureDefaultProfile(in: context)
            }
        }
    }

    // MARK: - Computed selections

    private var activeFocusSession: FocusSession? {
        sessions.first(where: { $0.isActive && $0.endedAt == nil })
    }

    private var nextReminderToday: VerboseReminder? {
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        return reminders.first(where: { $0.scheduledAt >= today && $0.scheduledAt < tomorrow })
    }

    private var nextTinyInboxItem: InboxItem? {
        inboxItems.first(where: { $0.estimateMinutes <= 5 })
    }

    private var secondarySuggestionInboxItem: InboxItem? {
        // Pick a different item than the “tiny” one if possible
        let tinyId = nextTinyInboxItem?.id
        return inboxItems.first(where: { $0.id != tinyId })
    }

    // MARK: - Actions

    private func startFocusSession(title: String, startStep: String? = nil) {
        // v1: keep this simple and predictable.
        // We'll default to 25 minutes unless the profile says otherwise later.
        let duration = 25 * 60

        let session = FocusSession(
            focusTitle: title,
            focusStartStep: startStep ?? "",
            durationSeconds: duration,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: nil,
            isActive: true
        )

        context.insert(session)

        do {
            try context.save()
            selectedTab = .focus
            toast("Focus session started.")
        } catch {
            print("❌ Save failed (startFocusSession):", error)
            toast("Couldn’t start focus. Try again.")
        }
    }

    private func makeInboxItemSmaller(_ item: InboxItem) {
        item.startStep = "Open what you need and do the smallest possible step for 2 minutes."
        item.estimateMinutes = 2

        do {
            try context.save()
            toast("Made it smaller. Starting is enough.")
        } catch {
            print("❌ Save failed (makeSmaller):", error)
            toast("Couldn’t update that item. Try again.")
        }
    }

    private func deleteInboxItem(_ item: InboxItem) {
        context.delete(item)
        do {
            try context.save()
            toast("Removed.")
        } catch {
            print("❌ Save failed (delete):", error)
            toast("Couldn’t remove it. Try again.")
        }
    }

    private func convertInboxItemToReminder(_ item: InboxItem, date: Date) {
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
            print("❌ Save failed (convertInboxItemToReminder):", error)
            toast("Couldn’t schedule that. Try again.")
            return
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

        toast("Scheduled. You don’t have to hold it in your head.")
    }

    private func toast(_ message: String) {
        withAnimation {
            toastMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                toastMessage = nil
            }
        }
    }
}

// MARK: - Small UI components

private struct TodayTaskCard: View {
    let title: String
    let startStep: String
    let estimateMinutes: Int
    let primaryButtonTitle: String
    let secondaryButtonTitle: String
    let primaryAction: () -> Void
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text("Start: \(startStep) (\(estimateMinutes) min)")
                .foregroundStyle(.secondary)

            HStack {
                Button(primaryButtonTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)

                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct TodayCard<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).foregroundStyle(.secondary)
            actions()
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct TodayEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You’re clear for now.")
                .font(.headline)
            Text("If something pops into your head, capture it — you don’t have to hold it.")
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct SuggestionRow: View {
    let title: String
    let subtitle: String
    let primaryTitle: String
    let secondaryTitle: String
    let primary: () -> Void
    let secondary: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(subtitle).foregroundStyle(.secondary)

            HStack {
                Button(primaryTitle, action: primary)
                    .buttonStyle(.bordered)

                Button(secondaryTitle, action: secondary)
                    .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct RefocusSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var secondsRemaining: Int = 30
    @State private var timer: Timer?

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Text("Refocus")
                    .font(.title2)
                    .bold()

                Text("Breathe slowly. You’re safe. You can start small.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("\(secondsRemaining)")
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .padding(.top, 6)

                Text("In… 2… 3… 4…  Out… 2… 3… 4…")
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Done") {
                    stopTimer()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom)
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        stopTimer()
                        dismiss()
                    }
                }
            }
            .onAppear { startTimer() }
            .onDisappear { stopTimer() }
        }
    }

    private func startTimer() {
        stopTimer()
        secondsRemaining = 30
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 {
                secondsRemaining -= 1
            } else {
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
