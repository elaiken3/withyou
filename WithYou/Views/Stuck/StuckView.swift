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
struct StuckView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedTab: AppTab

    /// When opened from a reminder ("Help me start"), that reminder is suggested first.
    let startingReminderId: UUID?

    @Query private var reminders: [VerboseReminder]
    @Query private var inboxItems: [InboxItem]
    @Query private var activeSessions: [FocusSession]

    @State private var suggestions: [StuckSuggestion] = []
    @State private var index: Int = 0
    @State private var startStepOverride: String?
    @State private var isFindingSmallerStep = false
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

    private func suggestionCard(_ suggestion: StuckSuggestion) -> some View {
        let isActiveFocus = suggestion.source == .activeFocus

        return VStack(alignment: .leading, spacing: 12) {
            Text(suggestion.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if isFindingSmallerStep {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding a smaller step…")
                        .foregroundStyle(.appSecondaryText)
                }
                .accessibilityElement(children: .combine)
            } else {
                Text("Start: \(displayStartStep)")
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
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
        .cardStyle()
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button {
            Haptics.tap()
            makeSmaller()
        } label: {
            Text("Make it smaller")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isFindingSmallerStep)

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

    private var current: StuckSuggestion? {
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
        errorMessage = nil
    }

    private func makeSmaller() {
        guard let suggestion = current, !isFindingSmallerStep else { return }
        let title = suggestion.title
        let currentStep = displayStartStep
        let suggestionIndex = index

        isFindingSmallerStep = true
        Task {
            let smaller = await SmallStepSuggester.smallerStep(for: title, current: currentStep)
            isFindingSmallerStep = false
            // The person moved on to a different suggestion while we were thinking.
            guard index == suggestionIndex else { return }
            startStepOverride = smaller
            let announcement: String = "Start: \(smaller)"
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private func start(_ suggestion: StuckSuggestion) {
        // Already focusing: just go back to it.
        if suggestion.source == .activeFocus {
            selectedTab = .focus
            dismiss()
            return
        }

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
            sourceKind = nil
            sourceId = nil
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
                startStep: displayStartStep,
                durationSeconds: 2 * 60,
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
