//
//  HelpMePickCard.swift
//  WithYou
//
//  Today's "Help me pick": one thing to do now, chosen from the Inbox and today's upcoming
//  reminders, with a gentle reason and a first step. Start, ask for something else, or leave it.
//

import Foundation
import SwiftUI

/// Something Today can suggest, plus what's needed to start a focus session on it.
struct PickCandidate: Equatable {
    var next: NextCandidate
    var kind: FocusSourceKind
    var sourceId: UUID
    /// The saved first step, used when the suggestion doesn't bring one.
    var startStep: String
}

/// The suggestion on screen.
struct PickChoice: Equatable {
    var candidate: PickCandidate
    var reason: String
    var firstStep: String
    var source: AISource
}

enum HelpMePick {
    static let maxCandidates = 30

    /// Today's upcoming reminders (soonest first), then Inbox items in the order given.
    /// Reminders that are done, already past, after today, or resting after "Not now"
    /// (checked within `restInterval`) are left out. At most `maxCandidates`.
    static func candidates(
        inbox: [InboxItem],
        reminders: [VerboseReminder],
        now: Date,
        restInterval: TimeInterval,
        calendar: Calendar = .current
    ) -> [PickCandidate] {
        let startOfToday = calendar.startOfDay(for: now)
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
            ?? startOfToday.addingTimeInterval(24 * 60 * 60)

        let upcoming = reminders
            .filter { reminder in
                !reminder.isDone
                    && reminder.scheduledAt >= now
                    && reminder.scheduledAt < startOfTomorrow
                    && !isResting(reminder.lastCheckedAt, now: now, restInterval: restInterval)
            }
            .sorted { $0.scheduledAt < $1.scheduledAt }

        var result: [PickCandidate] = []
        for reminder in upcoming {
            result.append(PickCandidate(
                next: NextCandidate(
                    id: reminder.id.uuidString,
                    title: reminder.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    estimateMinutes: reminder.estimateMinutes > 0 ? reminder.estimateMinutes : nil,
                    scheduledAt: reminder.scheduledAt
                ),
                kind: .reminder,
                sourceId: reminder.id,
                startStep: reminder.startStep
            ))
        }
        for item in inbox {
            result.append(PickCandidate(
                next: NextCandidate(
                    id: item.id.uuidString,
                    title: item.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    estimateMinutes: item.estimateMinutes > 0 ? item.estimateMinutes : nil,
                    scheduledAt: nil
                ),
                kind: .inbox,
                sourceId: item.id,
                startStep: item.startStep
            ))
        }

        let titled = result.filter { !$0.next.title.isEmpty }
        return Array(titled.prefix(maxCandidates))
    }

    /// "Help me pick" is only offered when there's a real choice to make.
    static func canOffer(_ candidates: [PickCandidate]) -> Bool {
        candidates.count >= 2
    }

    /// The candidates still in play after "Something else", in their original order.
    static func remaining(_ candidates: [PickCandidate], excluding excluded: Set<String>) -> [PickCandidate] {
        candidates.filter { !excluded.contains($0.next.id) }
    }

    /// The candidate a suggestion names, if it is one of `candidates`.
    static func match(_ suggestion: NextSuggestion, in candidates: [PickCandidate]) -> PickCandidate? {
        candidates.first { $0.next.id == suggestion.candidateId }
    }

    /// The first step to start with: the suggested one, else the saved one, else a simple one.
    static func startStep(for suggestion: NextSuggestion, candidate: PickCandidate) -> String {
        let suggested = suggestion.firstStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if !suggested.isEmpty { return suggested }
        let saved = candidate.startStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if !saved.isEmpty { return saved }
        return SmallStepSuggester.ruleBasedStep(for: candidate.next.title, current: "")
    }

    private static func isResting(_ lastCheckedAt: Date?, now: Date, restInterval: TimeInterval) -> Bool {
        guard let lastCheckedAt else { return false }
        return now.timeIntervalSince(lastCheckedAt) < restInterval
    }
}

/// One suggestion at a time. Asks when it appears and again after "Something else";
/// "Not now" (or leaving Today) cancels a request that is still running.
struct HelpMePickCard: View {
    let candidates: [PickCandidate]
    let energy: EnergyLevel?
    var onStart: (_ candidate: PickCandidate, _ firstStep: String) -> Void
    var onClose: () -> Void

    @State private var excluded: Set<String> = []
    @State private var choice: PickChoice?
    @State private var isLoading = true
    @State private var round = 0

    private var remainingCount: Int {
        HelpMePick.remaining(candidates, excluding: excluded).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help me pick")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.appSecondaryText)
                .accessibilityAddTraits(.isHeader)

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Looking at what’s here…")
                        .foregroundStyle(.appSecondaryText)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            } else if let choice {
                suggestion(choice)
            } else {
                Text("That’s everything here for now. Nothing has to happen right now.")
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            buttons
        }
        .cardStyle()
        .task(id: round) {
            await ask()
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func suggestion(_ choice: PickChoice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(choice.candidate.next.title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let time = choice.candidate.next.scheduledAt {
                Text("At \(time.timeText).")
                    .foregroundStyle(.appSecondaryText)
            }

            Text(choice.reason)
                .foregroundStyle(.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Start: \(choice.firstStep)")
                .foregroundStyle(.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)

        AIAttributionLabel(source: choice.source)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if !isLoading, let choice {
                Button {
                    Haptics.tap()
                    onStart(choice.candidate, choice.firstStep)
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityHint("Opens a focus session for this")

                if remainingCount > 1 {
                    Button {
                        Haptics.tap()
                        somethingElse()
                    } label: {
                        Text("Something else")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            Button {
                Haptics.tap()
                onClose()
            } label: {
                Text(!isLoading && choice == nil ? "Okay" : "Not now")
                    .foregroundStyle(.appSecondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .padding(.top, 2)
    }

    // MARK: - Asking

    private func somethingElse() {
        if let choice {
            excluded.insert(choice.candidate.next.id)
        }
        choice = nil
        isLoading = true
        round += 1
    }

    private func ask() async {
        let pool = HelpMePick.remaining(candidates, excluding: excluded)
        guard !pool.isEmpty else {
            choice = nil
            isLoading = false
            return
        }

        isLoading = true
        let answer = await AIService.suggestNext(
            from: pool.map { $0.next },
            energy: energy,
            minutesAvailable: nil
        )
        // Closed or asked again while waiting.
        guard !Task.isCancelled else { return }

        if let answer, let candidate = HelpMePick.match(answer.value, in: pool) {
            let picked = PickChoice(
                candidate: candidate,
                reason: answer.value.reason,
                firstStep: HelpMePick.startStep(for: answer.value, candidate: candidate),
                source: answer.source
            )
            choice = picked
            let announcement: String = "\(picked.candidate.next.title). \(picked.reason)"
            AccessibilityNotification.Announcement(announcement).post()
        } else {
            choice = nil
        }
        isLoading = false
    }
}
