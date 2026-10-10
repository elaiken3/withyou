//
//  TodayView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedTab: AppTab

    /// Unfinished reminders, soonest first.
    @Query private var reminders: [VerboseReminder]

    /// Unsorted so manual order (sortIndex) or newest-first can be applied below.
    @Query private var inboxItems: [InboxItem]

    @Query private var activeSessions: [FocusSession]

    /// The most recent completed sessions; filtered to today in memory.
    @Query private var recentCompletedSessions: [FocusSession]

    @Query private var appStates: [AppState]
    @Query(sort: \UserProfile.createdAt) private var profiles: [UserProfile]

    @AppStorage("inboxManualPrioritizationEnabled") private var manualPrioritizationEnabled: Bool = true

    /// Optional energy check-in. Stored with the day it was set, so it quietly resets each morning.
    @AppStorage("todayEnergyLevel") private var energyLevelRaw: String = ""
    @AppStorage("todayEnergyDay") private var energyDay: Double = 0

    /// Bumped every minute and when the app comes back, so time-based cards stay current.
    @State private var now = Date()

    @State private var toast: Toast?
    @State private var showRefocus = false
    @State private var showProfiles = false
    @State private var stuckPresentation: StuckPresentation?
    @State private var schedulingInboxItem: InboxItem?
    @State private var editingReminder: VerboseReminder?
    @State private var editingInboxItem: InboxItem?
    /// The Inbox item whose "Break it down" steps are showing.
    @State private var breakingDownItemId: UUID?
    /// "Help me pick" is showing its suggestion card.
    @State private var isPicking = false

    /// "Not now" / "Ask later" hide a reminder for this long.
    private static let restInterval: TimeInterval = 90 * 60
    /// Missed reminders older than this are let go quietly instead of asked about.
    private static let missedMaxAge: TimeInterval = 14 * 24 * 60 * 60

    init(selectedTab: Binding<AppTab> = .constant(.today)) {
        self._selectedTab = selectedTab

        _reminders = Query(
            filter: #Predicate<VerboseReminder> { (reminder: VerboseReminder) in
                reminder.isDone == false
            },
            sort: [SortDescriptor<VerboseReminder>(\.scheduledAt, order: .forward)]
        )

        _activeSessions = Query(
            filter: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            },
            sort: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )

        var completed = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { (s: FocusSession) in
                s.completedLoggedAt != nil
            },
            sortBy: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )
        completed.fetchLimit = 20
        _recentCompletedSessions = Query(completed)
    }

    var body: some View {
        // Everything the screen shows is worked out once per update.
        let state = makeState()

        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {

                        energyRow(state.energy)

                        // STILL RELEVANT (one missed reminder; neutral, asked once)
                        if let missed = state.missed {
                            stillRelevantCard(missed, profile: state.profile)
                        }

                        // RIGHT NOW (one card)
                        SectionHeader(title: "Right now")
                        rightNowCard(state)
                        helpMePick(state)

                        // OPTIONAL
                        energySection(state)

                        // SUPPORT
                        SectionHeader(title: "Reset")
                            .padding(.top, 4)
                        resetButtons(state)

                        // Gentle Inbox note (no guilt)
                        if !state.orderedInbox.isEmpty {
                            Text("Your Inbox is holding ^[\(state.orderedInbox.count) thought](inflect: true). You don’t need to clear it today.")
                                .font(.footnote)
                                .foregroundStyle(.appSecondaryText)
                                .padding(.top, 4)
                        }

                        if !state.completedToday.isEmpty {
                            SectionHeader(title: "Completed today")
                                .padding(.top, 6)

                            ForEach(state.completedToday) { session in
                                completedRow(session)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showProfiles = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showRefocus) {
                RefocusView()
            }
            .sheet(item: $schedulingInboxItem) { item in
                ScheduleSheetV2(
                    title: item.title,
                    startStep: item.startStep,
                    estimate: item.estimateMinutes
                ) { date in
                    schedule(item, at: date)
                }
                .presentationBackground(Color.appBackground)
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
            .sheet(item: $stuckPresentation) { presentation in
                StuckView(selectedTab: $selectedTab, startingReminderId: presentation.reminderId)
                    .presentationBackground(Color.appBackground)
            }
            .toast($toast)
            .tint(.appAccent)
        }
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
            now = Date()
            // A cold launch from a notification sets the route before this view exists.
            handlePendingRoute()
        }
        .onChange(of: AppRouter.shared.pendingRoute) { _, _ in
            handlePendingRoute()
        }
        // Another screen needs its sheet up (see `AppRouter.closeAllSheets()`).
        .onChange(of: AppRouter.shared.closeSheetsRequest) { _, _ in
            closeSheets()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                now = Date()
            }
        }
    }

    // MARK: - Snapshot

    private struct TodayState {
        let profile: UserProfile?
        let energy: EnergyLevel
        /// The energy the person actually picked today; nil when they didn't (AI gets nil).
        let checkedInEnergy: EnergyLevel?
        let orderedInbox: [InboxItem]
        let activeSession: FocusSession?
        let missed: VerboseReminder?
        let nextReminder: VerboseReminder?
        let rightNowItem: InboxItem?
        let energyItem: InboxItem?
        let unfinishedToday: [VerboseReminder]
        let canLetTodayRest: Bool
        let completedToday: [FocusSession]
        /// What "Help me pick" can choose from: today's upcoming reminders, then the Inbox.
        let pickCandidates: [PickCandidate]
    }

    private func makeState() -> TodayState {
        let calendar = Calendar.current
        let current = max(now, Date())
        let profile = activeProfile
        let startOfToday = calendar.startOfDay(for: current)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(24 * 60 * 60)

        // "Not now" / "Ask later" give a reminder a quiet 90 minutes.
        func isResting(_ reminder: VerboseReminder) -> Bool {
            guard let checked = reminder.lastCheckedAt else { return false }
            return current.timeIntervalSince(checked) < Self.restInterval
        }

        let ordered = orderedInbox()
        let checkedInEnergy = EnergyCheckIn.level(raw: energyLevelRaw, day: energyDay, on: current)
        let energy = checkedInEnergy ?? .okay
        let active = activeSessions.first

        // One missed reminder at most (no backlog, no overdue): the most recent one.
        let missed = reminders
            .filter { reminder in
                reminder.scheduledAt < current
                    && current.timeIntervalSince(reminder.scheduledAt) <= Self.missedMaxAge
                    && !isResting(reminder)
            }
            .max(by: { $0.scheduledAt < $1.scheduledAt })

        // Later today, not done, not resting. Reminders whose time passed are "Still relevant?".
        let next = reminders.first { reminder in
            reminder.scheduledAt >= current
                && reminder.scheduledAt < startOfTomorrow
                && !isResting(reminder)
        }

        // Right now falls back to the Inbox; on a low-energy day, the smallest thing in it.
        var rightNowItem: InboxItem?
        if active == nil && next == nil {
            rightNowItem = energy == .low
                ? ordered.min(by: { $0.estimateMinutes < $1.estimateMinutes })
                : ordered.first
        }
        let rightNowId = rightNowItem?.id
        let energyItem: InboxItem? = energy == .low ? nil : ordered.first(where: { $0.id != rightNowId })

        let unfinishedToday = reminders.filter { $0.scheduledAt >= startOfToday && $0.scheduledAt < startOfTomorrow }
        let eveningHour = profile?.eveningHour ?? 19
        let canLetTodayRest = calendar.component(.hour, from: current) >= eveningHour && !unfinishedToday.isEmpty

        let completedToday = recentCompletedSessions
            .filter { ($0.completedLoggedAt ?? .distantPast) >= startOfToday }
            .sorted { ($0.completedLoggedAt ?? .distantPast) > ($1.completedLoggedAt ?? .distantPast) }

        let pickCandidates = HelpMePick.candidates(
            inbox: ordered,
            reminders: reminders,
            now: current,
            restInterval: Self.restInterval,
            calendar: calendar
        )

        return TodayState(
            profile: profile,
            energy: energy,
            checkedInEnergy: checkedInEnergy,
            orderedInbox: ordered,
            activeSession: active,
            missed: missed,
            nextReminder: next,
            rightNowItem: rightNowItem,
            energyItem: energyItem,
            unfinishedToday: unfinishedToday,
            canLetTodayRest: canLetTodayRest,
            completedToday: completedToday,
            pickCandidates: pickCandidates
        )
    }

    private var activeProfile: UserProfile? {
        if let id = appStates.first?.activeProfileId,
           let match = profiles.first(where: { $0.id == id }) {
            return match
        }
        return profiles.first
    }

    /// Manual order drives Today's suggestions when it's on; otherwise newest first.
    private func orderedInbox() -> [InboxItem] {
        if manualPrioritizationEnabled {
            return inboxItems.sorted { a, b in
                switch (a.sortIndex, b.sortIndex) {
                case let (ai?, bi?): return ai < bi
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return a.createdAt > b.createdAt
                }
            }
        }
        return inboxItems.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Energy check-in

    // Never required. Unset (or set on another day) reads as "Okay" here, and as nothing
    // for AI requests (see `EnergyCheckIn`).
    private func setEnergy(_ level: EnergyLevel) {
        energyLevelRaw = level.rawValue
        energyDay = EnergyCheckIn.dayValue(for: Date())
    }

    private func energyRow(_ energy: EnergyLevel) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                energyLabel
                energyChips(energy)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                energyLabel
                HStack(spacing: 8) {
                    energyChips(energy)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                energyLabel
                energyChips(energy)
            }
        }
    }

    private var energyLabel: some View {
        Text("Energy today:")
            .font(.footnote)
            .foregroundStyle(.appSecondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func energyChips(_ energy: EnergyLevel) -> some View {
        ForEach(EnergyLevel.allCases) { level in
            let isSelected = level == energy
            Button {
                Haptics.tap()
                setEnergy(level)
            } label: {
                Text(level.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.appAccent : Color.appSecondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(isSelected ? Color.appAccent.opacity(0.14) : Color.appSurface)
                    )
                    .overlay(
                        Capsule().stroke(.appHairline.opacity(0.10), lineWidth: 1)
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(level.title) energy")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    // MARK: - Still relevant?

    private func stillRelevantCard(_ missed: VerboseReminder, profile: UserProfile?) -> some View {
        TodayCard(
            title: "Still relevant?",
            subtitle: "“\(missed.title)” was planned for \(missed.scheduledAt.friendlyDayTime). No problem either way.",
            onEdit: { editingReminder = missed }
        ) {
            ButtonRow {
                Button {
                    Haptics.tap()
                    moveLaterToday(missed, profile: profile)
                } label: {
                    Text("Later today")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Haptics.tap()
                    askLater(missed)
                } label: {
                    Text("Ask later")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button {
                    Haptics.tap()
                    letGo(missed)
                } label: {
                    Text("Let it go")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Right now

    @ViewBuilder
    private func rightNowCard(_ state: TodayState) -> some View {
        if let active = state.activeSession {
            activeSessionCard(active)
        } else if let next = state.nextReminder {
            nextReminderCard(next, profile: state.profile)
        } else if let item = state.rightNowItem {
            inboxRightNowCard(item, profile: state.profile)
        } else {
            TodayCard(
                title: "You’re clear for now.",
                subtitle: "If something pops into your head, capture it. You don’t have to hold it."
            ) {
                EmptyView()
            }
        }
    }

    private func activeSessionCard(_ active: FocusSession) -> some View {
        let hasBegun = active.startedAt != nil
        return TodayCard(
            title: hasBegun ? "You’re in a focus session" : "Your focus session is ready",
            subtitle: "Focusing on: \(active.focusTitle)"
        ) {
            ButtonRow {
                Button {
                    Haptics.tap()
                    selectedTab = .focus
                } label: {
                    Text(hasBegun ? "Resume focus" : "Open focus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Haptics.tap()
                    showRefocus = true
                } label: {
                    Text("Refocus (30 sec)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel("Refocus, 1 minute")
            }
        }
    }

    private func nextReminderCard(_ next: VerboseReminder, profile: UserProfile?) -> some View {
        TodayCard(
            title: next.title,
            subtitle: "At \(next.scheduledAt.timeText). \(stepLine(next.startStep, minutes: next.estimateMinutes))",
            onEdit: { editingReminder = next }
        ) {
            ButtonRow {
                Button {
                    Haptics.tap()
                    startFocus(
                        title: next.title,
                        startStep: next.startStep,
                        sourceKind: .reminder,
                        sourceId: next.id,
                        profile: profile
                    )
                } label: {
                    Text("Start a focus session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Haptics.tap()
                    notNow(next)
                } label: {
                    Text("Not now")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }

    private func inboxRightNowCard(_ item: InboxItem, profile: UserProfile?) -> some View {
        let isBreakingDown = breakingDownItemId == item.id
        return TodayCard(
            title: item.title,
            subtitle: stepLine(item.startStep, minutes: item.estimateMinutes),
            onEdit: { editingInboxItem = item }
        ) {
            ButtonRow {
                Button {
                    Haptics.tap()
                    startFocus(
                        title: item.title,
                        startStep: item.startStep,
                        sourceKind: .inbox,
                        sourceId: item.id,
                        profile: profile
                    )
                } label: {
                    Text("Do the first step")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    Haptics.tap()
                    breakingDownItemId = item.id
                } label: {
                    Text("Break it down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(isBreakingDown)
                .accessibilityHint("Shows a few tiny steps to pick from")
            }

            if isBreakingDown {
                BreakDownView(
                    title: item.title,
                    currentStep: item.startStep,
                    onPick: { step, index in
                        useFirstStep(step, at: index, for: item.id)
                    },
                    onClose: {
                        breakingDownItemId = nil
                    }
                )
            }
        }
    }

    // MARK: - Help me pick

    /// A quiet offer under Right now when there's a real choice; one suggestion at a time.
    @ViewBuilder
    private func helpMePick(_ state: TodayState) -> some View {
        if isPicking {
            HelpMePickCard(
                candidates: state.pickCandidates,
                energy: state.checkedInEnergy,
                onStart: { candidate, firstStep in
                    isPicking = false
                    startFocus(
                        title: candidate.next.title,
                        startStep: firstStep,
                        sourceKind: candidate.kind,
                        sourceId: candidate.sourceId,
                        profile: state.profile
                    )
                },
                onClose: {
                    isPicking = false
                }
            )
        } else if state.activeSession == nil && HelpMePick.canOffer(state.pickCandidates) {
            Button {
                Haptics.tap()
                isPicking = true
            } label: {
                Label("Help me pick", systemImage: "wand.and.stars")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Suggests one thing to do now, from your Inbox and today’s plan")
        }
    }

    // MARK: - If you have energy

    @ViewBuilder
    private func energySection(_ state: TodayState) -> some View {
        if state.energy == .low {
            Text("Rest counts too.")
                .foregroundStyle(.appSecondaryText)
                .padding(.top, 4)
        } else {
            SectionHeader(title: "If you have energy")
                .padding(.top, 4)

            if let item = state.energyItem {
                TodayCard(
                    title: item.title,
                    subtitle: stepLine(item.startStep, minutes: item.estimateMinutes),
                    onEdit: { editingInboxItem = item }
                ) {
                    ButtonRow {
                        Button {
                            Haptics.tap()
                            schedulingInboxItem = item
                        } label: {
                            Text("Schedule")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            Haptics.tap()
                            letGo(item)
                        } label: {
                            Text("Let it go")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            } else {
                Text("Nothing extra needed today.")
                    .foregroundStyle(.appSecondaryText)
            }
        }
    }

    // MARK: - Reset

    @ViewBuilder
    private func resetButtons(_ state: TodayState) -> some View {
        resetButton("Refocus (1 minute)", systemImage: "wind") {
            showRefocus = true
        }

        resetButton("I’m stuck", systemImage: "hand.raised") {
            stuckPresentation = StuckPresentation(reminderId: nil)
        }

        if state.canLetTodayRest {
            resetButton("Let today rest", systemImage: "moon") {
                letTodayRest(state.unfinishedToday, profile: state.profile)
            }
            .accessibilityHint("Moves today’s remaining reminders to tomorrow morning")
        }
    }

    private func resetButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // MARK: - Completed today

    private func completedRow(_ session: FocusSession) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.appAccent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.focusTitle)
                    .font(.headline)
                    .foregroundStyle(.appPrimaryText)

                Text("That counted.")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func stepLine(_ step: String, minutes: Int) -> String {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "About \(minutes) min" : "Start: \(trimmed) (\(minutes) min)"
    }

    // MARK: - Routing

    private struct StuckPresentation: Identifiable {
        let id = UUID()
        let reminderId: UUID?
    }

    private enum RoutedSheet {
        case stuck(UUID?)
        case reminder(UUID)
    }

    /// Takes `.stuck` and `.reminder` routes (see the contract in AppRouter.swift).
    private func handlePendingRoute() {
        guard let route = AppRouter.shared.pendingRoute else { return }
        switch route {
        case .stuck(let reminderId):
            AppRouter.shared.consume()
            present(.stuck(reminderId))
        case .reminder(let id):
            AppRouter.shared.consume()
            present(.reminder(id))
        default:
            break
        }
    }

    private var isPresentingSheet: Bool {
        showRefocus || showProfiles || stuckPresentation != nil || schedulingInboxItem != nil
            || editingReminder != nil || editingInboxItem != nil
    }

    /// Only one sheet can be up at a time, and other screens (voice capture, Refocus, the other
    /// tabs) present their own: close whatever is open anywhere first, then present.
    private func present(_ sheet: RoutedSheet) {
        guard isPresentingSheet || AppRouter.shared.isSheetUp else {
            show(sheet)
            return
        }

        closeSheets()
        AppRouter.shared.closeAllSheets()

        Task {
            try? await Task.sleep(for: .milliseconds(500))
            show(sheet)
        }
    }

    private func closeSheets() {
        showRefocus = false
        showProfiles = false
        stuckPresentation = nil
        schedulingInboxItem = nil
        editingReminder = nil
        editingInboxItem = nil
    }

    private func show(_ sheet: RoutedSheet) {
        switch sheet {
        case .stuck(let reminderId):
            stuckPresentation = StuckPresentation(reminderId: reminderId)
        case .reminder(let id):
            // Already finished or let go: nothing to show, and that's fine.
            if let reminder = fetchReminder(id: id) {
                editingReminder = reminder
            }
        }
    }

    // MARK: - Lookups

    private func fetchReminder(id: UUID) -> VerboseReminder? {
        var descriptor = FetchDescriptor<VerboseReminder>(
            predicate: #Predicate<VerboseReminder> { (reminder: VerboseReminder) in
                reminder.id == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func fetchInboxItem(id: UUID) -> InboxItem? {
        var descriptor = FetchDescriptor<InboxItem>(
            predicate: #Predicate<InboxItem> { (item: InboxItem) in
                item.id == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Actions: focus

    private func startFocus(
        title: String,
        startStep: String,
        sourceKind: FocusSourceKind,
        sourceId: UUID,
        profile: UserProfile?
    ) {
        let profileMinutes = profile?.defaultFocusMinutes ?? 25
        let minutes = profileMinutes > 0 ? profileMinutes : 25

        if sourceKind == .reminder, let reminder = fetchReminder(id: sourceId) {
            reminder.isStarted = true
        }

        do {
            // Not begun yet: the Focus tab opens on Brain Dump first, then "Begin Focus".
            try FocusSessionStore.start(
                title: title,
                startStep: startStep,
                durationSeconds: minutes * 60,
                sourceKind: sourceKind,
                sourceId: sourceId,
                beginImmediately: false,
                in: context
            )
            Haptics.success()
            selectedTab = .focus
        } catch {
            Haptics.error()
            print("❌ Save failed (startFocus):", error)
            toast = Toast(text: "Couldn’t start focus just now. Try again.")
        }
    }

    // MARK: - Actions: reminders

    /// "Not now" on the Right now card: hides it for a while, no questions.
    private func notNow(_ reminder: VerboseReminder) {
        let id = reminder.id
        let previous = reminder.lastCheckedAt
        reminder.lastCheckedAt = Date()
        do {
            try context.save()
            now = Date()
            toast = Toast(text: "No problem. It can wait.", actionTitle: "Undo", action: {
                guard let stored = fetchReminder(id: id) else { return }
                stored.lastCheckedAt = previous
                try? context.save()
            })
        } catch {
            print("❌ Save failed (notNow):", error)
            toast = Toast(text: "Couldn’t update that just now. Try again.")
        }
    }

    private func moveLaterToday(_ reminder: VerboseReminder, profile: UserProfile?) {
        let current = Date()
        let target = ReminderStore.thisEvening(profile: profile, now: current)
            ?? ReminderStore.roundedUp(current.addingTimeInterval(30 * 60))
        let id = reminder.id
        let previousDate = reminder.scheduledAt

        do {
            try ReminderStore.reschedule(reminder, to: target, in: context)
            Haptics.success()
            toast = Toast(text: "Moved to \(target.timeText).", actionTitle: "Undo", action: {
                guard let stored = fetchReminder(id: id) else { return }
                try? ReminderStore.reschedule(stored, to: previousDate, in: context)
            })
        } catch {
            Haptics.error()
            print("❌ Save failed (moveLaterToday):", error)
            toast = Toast(text: "Couldn’t move it just now. Try again.")
        }
    }

    private func askLater(_ reminder: VerboseReminder) {
        reminder.lastCheckedAt = Date()
        do {
            try context.save()
            now = Date()
            toast = Toast(text: "Okay. I’ll check once more later.")
        } catch {
            print("❌ Save failed (askLater):", error)
            toast = Toast(text: "Couldn’t update that just now. Try again.")
        }
    }

    private struct ReminderSnapshot {
        let id: UUID
        let title: String
        let why: String
        let startStep: String
        let estimateMinutes: Int
        let scheduledAt: Date
        let createdAt: Date
        let isStarted: Bool
        let lastCheckedAt: Date?

        init(_ reminder: VerboseReminder) {
            id = reminder.id
            title = reminder.title
            why = reminder.why
            startStep = reminder.startStep
            estimateMinutes = reminder.estimateMinutes
            scheduledAt = reminder.scheduledAt
            createdAt = reminder.createdAt
            isStarted = reminder.isStarted
            lastCheckedAt = reminder.lastCheckedAt
        }
    }

    private func letGo(_ reminder: VerboseReminder) {
        let snapshot = ReminderSnapshot(reminder)
        do {
            try ReminderStore.letGo(reminder, in: context)
            toast = Toast(text: "Okay. Letting it go.", actionTitle: "Undo", action: {
                restore(snapshot)
            })
        } catch {
            Haptics.error()
            print("❌ Save failed (letGo reminder):", error)
            toast = Toast(text: "Couldn’t let it go just now. Try again.")
        }
    }

    private func restore(_ snapshot: ReminderSnapshot) {
        let reminder = VerboseReminder(
            title: snapshot.title,
            why: snapshot.why,
            startStep: snapshot.startStep,
            estimateMinutes: snapshot.estimateMinutes,
            scheduledAt: snapshot.scheduledAt,
            createdAt: snapshot.createdAt,
            isStarted: snapshot.isStarted,
            isDone: false,
            lastCheckedAt: snapshot.lastCheckedAt
        )
        reminder.id = snapshot.id
        context.insert(reminder)
        do {
            try context.save()
            ReminderStore.refreshNotification(for: reminder)
        } catch {
            print("❌ Save failed (restore reminder):", error)
        }
    }

    /// Evening only: everything still planned for today moves to tomorrow morning.
    private func letTodayRest(_ items: [VerboseReminder], profile: UserProfile?) {
        guard !items.isEmpty else { return }
        let target = ReminderStore.nextMorning(profile: profile, after: Date())

        var previousDates: [UUID: Date] = [:]
        for reminder in items {
            previousDates[reminder.id] = reminder.scheduledAt
        }

        do {
            for reminder in items {
                try ReminderStore.reschedule(reminder, to: target, in: context)
            }
            // A resting day gets no daily check-in either.
            DailyCheckIn.letTodayRest()
            Haptics.success()
            let toRestore = previousDates
            toast = Toast(text: "Moved to tomorrow. Rest well.", actionTitle: "Undo", action: {
                for (id, date) in toRestore {
                    guard let stored = fetchReminder(id: id) else { continue }
                    try? ReminderStore.reschedule(stored, to: date, in: context)
                }
                DailyCheckIn.undoLetTodayRest()
            })
        } catch {
            Haptics.error()
            print("❌ Save failed (letTodayRest):", error)
            toast = Toast(text: "Couldn’t move everything just now. Try again.")
        }
    }

    // MARK: - Actions: Inbox

    /// A step picked from "Break it down" becomes the item's first step, with Undo.
    private func useFirstStep(_ step: String, at index: Int, for itemId: UUID) {
        breakingDownItemId = nil
        guard let stored = fetchInboxItem(id: itemId) else { return }
        let oldStep = stored.startStep
        let oldEstimate = stored.estimateMinutes
        let change = BreakDownChoice.change(picking: step, at: index, previousEstimate: oldEstimate)

        stored.startStep = change.startStep
        stored.estimateMinutes = change.estimateMinutes
        do {
            try context.save()
            Haptics.success()
            toast = Toast(text: "New first step. Starting is enough.", actionTitle: "Undo", action: {
                guard let again = fetchInboxItem(id: itemId) else { return }
                again.startStep = oldStep
                again.estimateMinutes = oldEstimate
                try? context.save()
            })
        } catch {
            print("❌ Save failed (useFirstStep):", error)
            toast = Toast(text: "Couldn’t update that just now. Try again.")
        }
    }

    private struct InboxSnapshot {
        let id: UUID
        let content: String
        let title: String
        let createdAt: Date
        let source: ItemSource
        let startStep: String
        let estimateMinutes: Int
        let sortIndex: Int?

        init(_ item: InboxItem) {
            id = item.id
            content = item.content
            title = item.title
            createdAt = item.createdAt
            source = item.source
            startStep = item.startStep
            estimateMinutes = item.estimateMinutes
            sortIndex = item.sortIndex
        }
    }

    private func letGo(_ item: InboxItem) {
        let snapshot = InboxSnapshot(item)
        context.delete(item)
        do {
            try context.save()
            toast = Toast(text: "Okay. Letting it go.", actionTitle: "Undo", action: {
                let restored = InboxItem(
                    content: snapshot.content,
                    title: snapshot.title,
                    createdAt: snapshot.createdAt,
                    source: snapshot.source,
                    startStep: snapshot.startStep,
                    estimateMinutes: snapshot.estimateMinutes,
                    sortIndex: snapshot.sortIndex
                )
                restored.id = snapshot.id
                context.insert(restored)
                try? context.save()
            })
        } catch {
            Haptics.error()
            print("❌ Save failed (letGo inbox):", error)
            toast = Toast(text: "Couldn’t let it go just now. Try again.")
        }
    }

    /// "Schedule" from "If you have energy": the thought becomes a reminder and leaves the Inbox.
    private func schedule(_ item: InboxItem, at date: Date) {
        let itemId = item.id
        let title = item.title
        let startStep = item.startStep
        let estimate = item.estimateMinutes

        Task {
            do {
                _ = try await ReminderStore.createAndSchedule(
                    title: title,
                    startStep: startStep,
                    estimateMinutes: estimate,
                    scheduledAt: date,
                    in: context
                )
                if let stored = fetchInboxItem(id: itemId) {
                    context.delete(stored)
                }
                try context.save()
                Haptics.success()
                toast = Toast(text: "Scheduled for \(date.friendlyDayTime).")
            } catch {
                Haptics.error()
                print("❌ Save failed (schedule inbox item):", error)
                toast = Toast(text: "Couldn’t schedule that just now. Try again.")
            }
        }
    }
}

// MARK: - Small building blocks

/// A Today card: title, optional subtitle, and actions. Tapping the card (or the VoiceOver
/// "Edit" action) opens the edit sheet when `onEdit` is set.
private struct TodayCard<Actions: View>: View {
    let title: String
    let subtitle: String?
    let onEdit: (() -> Void)?
    let actions: () -> Actions

    init(
        title: String,
        subtitle: String? = nil,
        onEdit: (() -> Void)? = nil,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.title = title
        self.subtitle = subtitle
        self.onEdit = onEdit
        self.actions = actions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            actions()
        }
        .cardStyle()
        .contentShape(Rectangle())
        .onTapGesture {
            guard let onEdit else { return }
            Haptics.tap()
            onEdit()
        }
    }

    @ViewBuilder
    private var header: some View {
        let text = VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)

        if let onEdit {
            text.accessibilityAction(named: "Edit") {
                onEdit()
            }
        } else {
            text
        }
    }
}

/// Buttons side by side when they fit, stacked at larger text sizes.
private struct ButtonRow<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                content()
            }
            VStack(spacing: 10) {
                content()
            }
        }
    }
}
