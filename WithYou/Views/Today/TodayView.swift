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

    // NOTE: Unsorted so we can apply dynamic ordering (manual sortIndex first, else createdAt).
    @Query private var inboxItems: [InboxItem]

    @Query(sort: \FocusSession.createdAt, order: .reverse) private var sessions: [FocusSession]

    @AppStorage("inboxManualPrioritizationEnabled") private var manualPrioritizationEnabled: Bool = true

    @State private var showRefocus = false
    @State private var showScheduleForInboxItem: InboxItem?
    @State private var toastMessage: String?
    @State private var showProfiles = false
    @State private var showRescheduleForReminder: VerboseReminder?
    @State private var showStuck = false
    @State private var editingReminder: VerboseReminder?
    @State private var editingInboxItem: InboxItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        // STILL RELEVANT (missed reminder, neutral)
                        if let missed = missedReminder {
                            TodayCard(
                                title: "Still relevant?",
                                subtitle: "“\(missed.title)” was scheduled for \(friendlyScheduledDateTime(missed.scheduledAt)). No problem if you missed it. Reschedule?"
                            ) {
                                Button("Today") {
                                    rescheduleMissedToToday(missed)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityLabel("Reschedule for today")

                                Button("Later") {
                                    markMissedChecked(missed) // sets lastCheckedAt + toast
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Ask again later")

                                Button("Not needed") {
                                    dismissMissedReminder(missed)
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Let this reminder go")
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.tap()
                                editingReminder = missed
                            }
                        }

                        // RIGHT NOW (one card)
                        Text("Right now")
                            .font(.headline)
                            .foregroundStyle(.appPrimaryText)
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
                                .accessibilityLabel("Resume focus session")

                                Button("Refocus (30 sec)") {
                                    Haptics.tap()
                                    showRefocus = true
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Start a 30 second refocus")
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
                                startFocusSession(
                                    title: next.title,
                                    startStep: next.startStep,
                                    sourceKind: .reminder,
                                    sourceId: next.id
                                )
                            } secondaryAction: {
                                Haptics.tap()
                                toast("No problem. It can wait.")
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.tap()
                                editingReminder = next
                            }

                        } else if let item = rightNowInboxItem {
                            TodayTaskCard(
                                title: item.title,
                                startStep: item.startStep,
                                estimateMinutes: item.estimateMinutes,
                                primaryButtonTitle: "Do the first step",
                                secondaryButtonTitle: "Make it smaller"
                            ) {
                                startFocusSession(
                                    title: item.title,
                                    startStep: item.startStep,
                                    sourceKind: .inbox,
                                    sourceId: item.id
                                )
                            } secondaryAction: {
                                Haptics.tap()
                                makeInboxItemSmaller(item)
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.tap()
                                editingInboxItem = item
                            }

                        } else {
                            TodayEmptyCard()
                                .padding(.horizontal)
                        }

                        // OPTIONAL SECTION
                        Text("If you have energy")
                            .font(.headline)
                            .foregroundStyle(.appPrimaryText)
                            .padding(.horizontal)

                        if let suggestion = ifYouHaveEnergyInboxItem {
                            SuggestionRow(
                                title: suggestion.title,
                                subtitle: "Start: \(suggestion.startStep) (\(suggestion.estimateMinutes) min)",
                                primaryTitle: "Schedule",
                                secondaryTitle: "Not needed"
                            ) {
                                Haptics.tap()
                                showScheduleForInboxItem = suggestion
                            } secondary: {
                                Haptics.tap()
                                deleteInboxItem(suggestion)
                            }
                            .padding(.horizontal)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                Haptics.tap()
                                editingInboxItem = suggestion
                            }
                        } else {
                            Text("Nothing extra needed today.")
                                .foregroundStyle(.appSecondaryText)
                                .padding(.horizontal)
                        }

                        // SUPPORT
                        Text("Reset")
                            .font(.headline)
                            .foregroundStyle(.appPrimaryText)
                            .padding(.horizontal)

                        Button {
                            Haptics.tap()
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
                        .accessibilityLabel("Start a 30 second refocus")

                        Button {
                            Haptics.tap()
                            showStuck = true
                        } label: {
                            HStack {
                                Image(systemName: "hand.raised")
                                Text("I’m stuck")
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .padding(.horizontal)
                        .accessibilityLabel("Open the stuck helper")

                        // Gentle Inbox indicator (no guilt)
                        if !orderedInboxItems.isEmpty {
                            Text("Inbox has \(orderedInboxItems.count) item(s). You don’t need to clear it today.")
                                .foregroundStyle(.appSecondaryText)
                                .font(.footnote)
                                .padding(.horizontal)
                                .padding(.top, 4)
                        }

                        if !completedFocusSessionsToday.isEmpty {
                            Text("Completed today")
                                .font(.headline)
                                .foregroundStyle(.appPrimaryText)
                                .padding(.horizontal)
                                .padding(.top, 6)

                            ForEach(completedFocusSessionsToday) { s in
                                CompletedCard(
                                    title: s.focusTitle,
                                    subtitle: "That counted."
                                )
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showRefocus) {
                RefocusSheet()
            }
            .sheet(item: $showScheduleForInboxItem) { item in
                ScheduleSheetV2(
                    title: item.title,
                    startStep: item.startStep,
                    estimate: item.estimateMinutes
                ) { date in
                    convertInboxItemToReminder(item, date: date)
                }
                .presentationBackground(Color.appBackground)
            }
            .sheet(item: $showRescheduleForReminder) { reminder in
                ScheduleSheetV2(
                    title: reminder.title,
                    startStep: reminder.startStep,
                    estimate: reminder.estimateMinutes
                ) { date in
                    rescheduleReminder(reminder, to: date)
                }
                .presentationBackground(Color.appBackground)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfiles = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(item: $editingInboxItem) { item in
                EditInboxItemSheet(item: item)
                    .presentationBackground(Color.appBackground)
            }
            .sheet(item: $editingReminder) { reminder in
                EditReminderSheet(reminder: reminder)
                    .presentationBackground(Color.appBackground)
            }
            .sheet(isPresented: $showProfiles) {
                NavigationStack { ProfilesView() }
            }
            .sheet(isPresented: $showStuck) {
                StuckView(
                    selectedTab: $selectedTab,
                    focusSessions: sessions,
                    reminders: reminders,
                    inboxItems: orderedInboxItems
                )
            }
            .tint(.appAccent)
        }
    }

    // MARK: - Ordered Inbox (manual order drives Today suggestions)

    private var orderedInboxItems: [InboxItem] {
        if manualPrioritizationEnabled {
            return inboxItems.sorted { a, b in
                switch (a.sortIndex, b.sortIndex) {
                case let (ai?, bi?): return ai < bi
                case (_?, nil):     return true
                case (nil, _?):     return false
                case (nil, nil):    return a.createdAt > b.createdAt
                }
            }
        } else {
            return inboxItems.sorted { $0.createdAt > $1.createdAt }
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

    /// One missed reminder (no backlog, no overdue)
    private var missedReminder: VerboseReminder? {
        let cooldown: TimeInterval = 90 * 60 // 90 minutes
        let maxAge: TimeInterval = 14 * 24 * 60 * 60 // 14 days
        let now = Date()

        let candidates = reminders.filter { r in
            r.scheduledAt < now
            && r.isDone == false
            && now.timeIntervalSince(r.scheduledAt) <= maxAge
            && (
                r.lastCheckedAt == nil
                || now.timeIntervalSince(r.lastCheckedAt!) > cooldown
            )
        }

        // Most recently missed (latest scheduledAt in the past)
        return candidates.max(by: { $0.scheduledAt < $1.scheduledAt })
    }

    // Manual order mapping:
    // Right now = first inbox item (if no focus session, no reminder today)
    // If you have energy = second inbox item
    private var rightNowInboxItem: InboxItem? {
        orderedInboxItems.first
    }

    private var ifYouHaveEnergyInboxItem: InboxItem? {
        guard orderedInboxItems.count > 1 else { return nil }
        return orderedInboxItems[1]
    }

    private var completedFocusSessionsToday: [FocusSession] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        return sessions
            .filter { s in
                guard let completed = s.completedLoggedAt else { return false }
                return completed >= startOfToday
            }
            .sorted { ($0.completedLoggedAt ?? .distantPast) > ($1.completedLoggedAt ?? .distantPast) }
    }

    private func friendlyScheduledDateTime(_ date: Date) -> String {
        let calendar = Calendar.current

        let datePart: String
        if calendar.isDateInToday(date) {
            datePart = "today"
        } else if calendar.isDateInYesterday(date) {
            datePart = "yesterday"
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMMM d" // March 12
            datePart = dateFormatter.string(from: date)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timePart = timeFormatter.string(from: date).lowercased()

        return "\(datePart) at \(timePart)"
    }

    // MARK: - Actions (UNCHANGED)

    private func startFocusSession(
        title: String,
        startStep: String? = nil,
        sourceKind: FocusSourceKind? = nil,
        sourceId: UUID? = nil
    ) {
        let duration = 25 * 60

        let session = FocusSession(
            focusTitle: title,
            focusStartStep: startStep ?? "",
            durationSeconds: duration,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: nil,
            isActive: true,
            completedLoggedAt: nil,
            sourceKindRaw: sourceKind?.rawValue,
            sourceId: sourceId
        )

        context.insert(session)

        do {
            try context.save()
            Haptics.success()
            selectedTab = .focus
            toast("Focus session started.")
        } catch {
            Haptics.error()
            print("❌ Save failed (startFocusSession):", error)
            toast("Couldn’t start focus. Try again.")
        }
    }

    private func markMissedChecked(_ reminder: VerboseReminder) {
        reminder.lastCheckedAt = Date()
        do {
            try context.save()
        } catch {
            print("❌ Save failed (markMissedChecked):", error)
        }
        toast("We’ll check again later to see if there was anything else.")
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
        Haptics.tap()
        Task {
            do {
                _ = try await ReminderStore.createAndSchedule(
                    title: item.title,
                    startStep: item.startStep,
                    estimateMinutes: item.estimateMinutes,
                    scheduledAt: date,
                    in: context
                )
                context.delete(item)
                try context.save()
                Haptics.success()
                toast("Scheduled. You don’t have to hold it in your head.")
            } catch {
                Haptics.error()
                print("❌ Save failed (convertInboxItemToReminder):", error)
                toast("Couldn’t schedule that. Try again.")
            }
        }
    }

    private func rescheduleReminder(_ reminder: VerboseReminder, to date: Date) {
        reminder.scheduledAt = date
        Haptics.tap()

        do {
            Haptics.success()
            try context.save()
        } catch {
            Haptics.error()
            print("❌ Save failed (rescheduleReminder):", error)
            toast("Couldn’t reschedule. Try again.")
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

        toast("Rescheduled.")
    }

    private func rescheduleMissedToToday(_ reminder: VerboseReminder) {
        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        let now = Date()
        let cal = Calendar.current
        var target = now.addingTimeInterval(30 * 60)

        if let p = profile {
            let startOfToday = cal.startOfDay(for: now)
            if let evening = cal.date(bySettingHour: p.eveningHour, minute: 0, second: 0, of: startOfToday),
               evening > now {
                target = evening
            }
        }

        reminder.scheduledAt = target
        reminder.lastCheckedAt = Date() // ✅ breathing cooldown starts now
        Haptics.tap()

        do {
            Haptics.success()
            try context.save()
        } catch {
            Haptics.error()
            print("❌ Save failed (rescheduleMissedToToday):", error)
            toast("Couldn’t reschedule. Try again.")
            return
        }

        // ✅ Cancel old pending request and schedule the new one
        NotificationManager.shared.cancelReminder(id: reminder.id)

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

        toast("We’ll check again later to see if there was anything else.")
    }

    private func dismissMissedReminder(_ reminder: VerboseReminder) {
        // ✅ Cancel any pending notification first
        NotificationManager.shared.cancelReminder(id: reminder.id)

        context.delete(reminder)
        do {
            try context.save()
            toast("We’ll check again later to see if there was anything else.")
        } catch {
            print("❌ Save failed (dismissMissedReminder):", error)
            toast("Couldn’t remove it. Try again.")
        }
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

// MARK: - Small UI components (updated styling only)

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
            Text(title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("Start: \(startStep) (\(estimateMinutes) min)")
                .foregroundStyle(.appSecondaryText)

            HStack {
                Button(primaryButtonTitle, action: primaryAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(primaryButtonTitle)
                    .accessibilityHint("Primary action for this card")

                Button(secondaryButtonTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(secondaryButtonTitle)
                    .accessibilityHint("Secondary action for this card")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

private struct TodayCard<Actions: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text(subtitle)
                .foregroundStyle(.appSecondaryText)

            actions()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

private struct TodayEmptyCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("You’re clear for now.")
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("If something pops into your head, capture it — you don’t have to hold it.")
                .foregroundStyle(.appSecondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
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
            Text(title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text(subtitle)
                .foregroundStyle(.appSecondaryText)

            HStack {
                Button(primaryTitle, action: primary)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(primaryTitle)
                    .accessibilityHint("Primary action for this card")

                Button(secondaryTitle, action: secondary)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(secondaryTitle)
                    .accessibilityHint("Secondary action for this card")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
    }
}

private struct RefocusSheet: View {
    var body: some View {
        RefocusView()
    }
}

private struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.appPrimaryText)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.appSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.appHairline.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }
}

private struct CompletedCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.green.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.green.opacity(0.18), radius: 14, x: 0, y: 6) // soft green glow
    }
}

// CompletionStore moved to Services/CompletionStore.swift
