//
//  StuckChooser.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/31/25.
//

import Foundation
import SwiftData

struct StuckSuggestion {
    enum Source { case activeFocus, reminder, inbox }

    let source: Source
    let title: String
    let startStep: String
    let estimateMinutes: Int

    // Kept so "Start 2 minutes" can link the focus session back to where it came from.
    let reminderId: UUID?
    let inboxId: UUID?
    let focusSessionId: UUID?
}

/// Picks a few small, concrete things to start on when the person feels stuck.
/// Never a list to work through: one suggestion at a time, with "Try a different one".
enum StuckChooser {

    static func suggestions(
        focusSessions: [FocusSession],
        reminders: [VerboseReminder],
        inboxItems: [InboxItem],
        startingReminderId: UUID? = nil,
        now: Date = Date()
    ) -> [StuckSuggestion] {

        var out: [StuckSuggestion] = []

        // A) The reminder the person asked for help with ("Help me start") comes first.
        var startingId: UUID?
        if let startingReminderId,
           let starting = reminders.first(where: { $0.id == startingReminderId && !$0.isDone }) {
            out.append(reminderSuggestion(starting))
            startingId = starting.id
        }

        // B) An active focus session is the next best thing to return to.
        if let active = focusSessions.first(where: { $0.isActive && $0.endedAt == nil }) {
            out.append(
                StuckSuggestion(
                    source: .activeFocus,
                    title: active.focusTitle,
                    startStep: normalizeStartStep(active.focusStartStep, fallbackTitle: active.focusTitle),
                    estimateMinutes: 2,
                    reminderId: nil,
                    inboxId: nil,
                    focusSessionId: active.id
                )
            )
            return out
        }

        // C1) A reminder coming up soon (within 6 hours), not done.
        if let soon = nextSoonReminder(reminders: reminders, now: now, hours: 6, excluding: startingId) {
            out.append(reminderSuggestion(soon))
        }

        // C2) The smallest Inbox item (newest first when estimates tie).
        let smallest = inboxItems.min { a, b in
            if a.estimateMinutes != b.estimateMinutes { return a.estimateMinutes < b.estimateMinutes }
            return a.createdAt > b.createdAt
        }
        if let smallest {
            out.append(inboxSuggestion(smallest))
        }

        // C3) The most recently captured Inbox item, if different.
        if let recent = inboxItems.max(by: { $0.createdAt < $1.createdAt }),
           recent.id != smallest?.id {
            out.append(inboxSuggestion(recent))
        }

        return out
    }

    private static func reminderSuggestion(_ reminder: VerboseReminder) -> StuckSuggestion {
        StuckSuggestion(
            source: .reminder,
            title: reminder.title,
            startStep: normalizeStartStep(reminder.startStep, fallbackTitle: reminder.title),
            estimateMinutes: min(reminder.estimateMinutes, 5),
            reminderId: reminder.id,
            inboxId: nil,
            focusSessionId: nil
        )
    }

    private static func inboxSuggestion(_ item: InboxItem) -> StuckSuggestion {
        StuckSuggestion(
            source: .inbox,
            title: item.title,
            startStep: normalizeStartStep(item.startStep, fallbackTitle: item.title),
            estimateMinutes: min(item.estimateMinutes, 5),
            reminderId: nil,
            inboxId: item.id,
            focusSessionId: nil
        )
    }

    private static func nextSoonReminder(
        reminders: [VerboseReminder],
        now: Date,
        hours: Int,
        excluding excludedId: UUID?
    ) -> VerboseReminder? {
        let windowEnd = now.addingTimeInterval(TimeInterval(hours * 3600))
        return reminders
            .filter { !$0.isDone && $0.id != excludedId && $0.scheduledAt >= now && $0.scheduledAt <= windowEnd }
            .min(by: { $0.scheduledAt < $1.scheduledAt })
    }

    /// The saved first step, or a rule-based one when it's empty.
    static func normalizeStartStep(_ step: String, fallbackTitle: String) -> String {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return SmallStepSuggester.ruleBasedStep(for: fallbackTitle, current: "")
    }
}
