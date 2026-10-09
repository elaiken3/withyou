//
//  StuckView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/31/25.
//

import Foundation
import SwiftUI
import SwiftData

/// "I'm stuck": one tiny, concrete thing to start on, for just two minutes.
/// Optionally, the person names what's in the way and gets one small step to try.
struct StuckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: AppTab

    /// When opened from a reminder ("Help me start"), that reminder is suggested first.
    let startingReminderId: UUID?

    @Query private var reminders: [VerboseReminder]
    @Query private var inboxItems: [InboxItem]
    @Query private var activeSessions: [FocusSession]

    /// Today's optional energy check-in (stored by TodayView). The coach hears it only if set today.
    @AppStorage("todayEnergyLevel") private var energyLevelRaw: String = ""
    @AppStorage("todayEnergyDay") private var energyDay: Double = 0

    @State private var suggestions: [StuckCandidate] = []
    @State private var index: Int = 0
    @State private var startStepOverride: String?
    @State private var isBreakingDown = false
    /// What the person said is in the way. While set, the coach's suggestion fills the card.
    @State private var coachBlocker: StuckBlocker?
    @State private var didLoad = false
    @State private var errorMessage: String?

    init(selectedTab: Binding<AppTab>, startingReminderId: UUID? = nil) {
        self._selectedTab = selectedTab
        self.startingReminderId = startingReminderId
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
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("I’m stuck")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.appPrimaryText)
                                .accessibilityAddTraits(.isHeader)

                            Text("Let’s do one tiny thing.")
                                .foregroundStyle(.appSecondaryText)
                        }

                        if let suggestion = current {
                            suggestionCard(suggestion)

                            if coachBlocker == nil {
                                coachChips
                            }
                        } else {
                            emptyCard
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.appSecondaryText)
                        }
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .tint(.appAccent)
            .onAppear {
                loadSuggestionsIfNeeded()
            }
        }
    }

    // MARK: - Pieces

    private func suggestionCard(_ suggestion: StuckCandidate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let blocker = coachBlocker {
                StuckCoachSection(
                    title: suggestion.title,
                    blocker: blocker,
                    energy: checkedInEnergy,
                    onTry: { help in
                        beginFocus(on: suggestion, step: help.step, minutes: help.minutes)
                    },
                    onSomethingElse: {
                        coachBlocker = nil
                    },
                    onNotNow: {
                        dismiss()
                    }
                )
            } else {
                startContent(suggestion)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func startContent(_ suggestion: StuckCandidate) -> some View {
        let isActiveFocus = suggestion.source == .activeFocus

        Text("Start: \(displayStartStep)")
            .foregroundStyle(.appSecondaryText)
            .fixedSize(horizontal: false, vertical: true)

        if isBreakingDown {
            BreakDownView(
                title: suggestion.title,
                currentStep: displayStartStep,
                onPick: { step, _ in
                    useStep(step)
                },
                onClose: {
                    isBreakingDown = false
                }
            )
        }

        Text(isActiveFocus ? "Your focus session is still here." : "Just 2 minutes. We’re only starting.")
            .font(.footnote)
            .foregroundStyle(.appSecondaryText)

        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                start(suggestion)
            } label: {
                Text(isActiveFocus ? "Back to focus" : "Start 2 minutes")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            // Side by side when they fit; stacked at larger text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    secondaryButtons
                }
                VStack(spacing: 10) {
                    secondaryButtons
                }
            }

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("Not now")
                    .foregroundStyle(.appSecondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button {
            Haptics.tap()
            errorMessage = nil
            isBreakingDown = true
        } label: {
            Text("Break it down")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isBreakingDown)
        .accessibilityHint("Shows a few tiny steps to pick from")

        if suggestions.count > 1 {
            Button {
                Haptics.tap()
                nextSuggestion()
            } label: {
                Text("Try a different one")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    /// Optional: name what's in the way and get one small step for it.
    private var coachChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: StuckCoachText.question)

                Text("If you like, pick what fits. You’ll get one small step to try.")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StuckBlockerChips { blocker in
                isBreakingDown = false
                errorMessage = nil
                coachBlocker = blocker
            }
        }
        .padding(.top, 4)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing to choose right now.")
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("You’re okay. A slow breath counts too.")
                .foregroundStyle(.appSecondaryText)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    // MARK: - State

    private var current: StuckCandidate? {
        guard !suggestions.isEmpty, index >= 0, index < suggestions.count else { return nil }
        return suggestions[index]
    }

    private var displayStartStep: String {
        if let override = startStepOverride,
           !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return current?.startStep ?? SmallStepSuggester.genericStep
    }

    private var checkedInEnergy: EnergyLevel? {
        EnergyCheckIn.level(raw: energyLevelRaw, day: energyDay, on: Date())
    }

    /// Suggestions are picked once per opening so they don't shuffle while the person reads.
    private func loadSuggestionsIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        suggestions = StuckChooser.suggestions(
            focusSessions: activeSessions,
            reminders: reminders,
            inboxItems: inboxItems,
            startingReminderId: startingReminderId
        )
        index = 0
        startStepOverride = nil
    }

    // MARK: - Actions

    private func nextSuggestion() {
        guard !suggestions.isEmpty else { return }
        index = (index + 1) % suggestions.count
        startStepOverride = nil
        isBreakingDown = false
        coachBlocker = nil
        errorMessage = nil
    }

    /// A step picked from "Break it down" becomes the first step for this start.
    private func useStep(_ step: String) {
        isBreakingDown = false
        startStepOverride = step
        let announcement: String = "Start: \(step)"
        AccessibilityNotification.Announcement(announcement).post()
    }

    private func start(_ suggestion: StuckCandidate) {
        // Already focusing: just go back to it, with the smaller first step if one was picked.
        if suggestion.source == .activeFocus {
            if let override = startStepOverride?.trimmingCharacters(in: .whitespacesAndNewlines),
               !override.isEmpty,
               let active = FocusSessionStore.activeSession(in: context) {
                active.focusStartStep = override
                do {
                    try context.save()
                } catch {
                    print("❌ Save failed (StuckView.start step):", error)
                }
            }
            selectedTab = .focus
            dismiss()
            return
        }

        beginFocus(on: suggestion, step: displayStartStep, minutes: 2)
    }

    /// Starts a short focus session on `suggestion` right away and opens the Focus tab.
    private func beginFocus(on suggestion: StuckCandidate, step: String, minutes: Int) {
        let sourceKind: FocusSourceKind?
        let sourceId: UUID?
        switch suggestion.source {
        case .reminder:
            sourceKind = .reminder
            sourceId = suggestion.reminderId
        case .inbox:
            sourceKind = .inbox
            sourceId = suggestion.inboxId
        case .activeFocus:
            // A fresh, short session on the same task, still linked to where it came from.
            let active = FocusSessionStore.activeSession(in: context)
            sourceKind = active?.sourceKindRaw.flatMap { FocusSourceKind(rawValue: $0) }
            sourceId = active?.sourceId
        }

        // Starting a new session ends the current one; keep any thoughts parked in it.
        if let active = FocusSessionStore.activeSession(in: context) {
            CompletionStore.moveLeftoverThoughtsToInbox(for: active, in: context)
        }

        if suggestion.source == .reminder,
           let reminderId = suggestion.reminderId,
           let reminder = reminders.first(where: { $0.id == reminderId }) {
            reminder.isStarted = true
        }

        do {
            // Linking the source means finishing the session also clears the item.
            try FocusSessionStore.start(
                title: suggestion.title,
                startStep: step,
                durationSeconds: max(1, minutes) * 60,
                sourceKind: sourceKind,
                sourceId: sourceId,
                beginImmediately: true,
                in: context
            )
            Haptics.success()
            selectedTab = .focus
            dismiss()
        } catch {
            Haptics.error()
            errorMessage = "Couldn’t start just now. Try again."
            print("❌ Save failed (StuckView.start):", error)
        }
    }
}
