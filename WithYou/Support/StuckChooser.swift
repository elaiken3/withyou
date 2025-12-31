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

    // Keep references so “Start 2 minutes” can optionally mark isStarted, etc. later.
    let reminderId: UUID?
    let inboxId: UUID?
    let focusSessionId: UUID?
}

enum StuckChooser {

    static func suggestions(
        focusSessions: [FocusSession],
        reminders: [VerboseReminder],
        inboxItems: [InboxItem],
        now: Date = Date()
    ) -> [StuckSuggestion] {

        // A) If there’s an active focus session, that’s the suggestion.
        if let active = focusSessions.first(where: { $0.isActive && $0.endedAt == nil }) {
            return [
                StuckSuggestion(
                    source: .activeFocus,
                    title: active.focusTitle,
                    startStep: normalizeStartStep(active.focusStartStep, fallbackTitle: active.focusTitle),
                    estimateMinutes: 2,
                    reminderId: nil,
                    inboxId: nil,
                    focusSessionId: active.id
                )
            ]
        }

        var out: [StuckSuggestion] = []

        // B1) Upcoming reminder soon (within 6 hours), not done
        if let soon = nextSoonReminder(reminders: reminders, now: now, hours: 6) {
            out.append(
                StuckSuggestion(
                    source: .reminder,
                    title: soon.title,
                    startStep: normalizeStartStep(soon.startStep, fallbackTitle: soon.title),
                    estimateMinutes: min(soon.estimateMinutes, 5),
                    reminderId: soon.id,
                    inboxId: nil,
                    focusSessionId: nil
                )
            )
        }

        // B2) Smallest inbox item (prefer <= 5)
        if let tiny = inboxItems
            .sorted(by: { $0.estimateMinutes < $1.estimateMinutes })
            .first
        {
            out.append(
                StuckSuggestion(
                    source: .inbox,
                    title: tiny.title,
                    startStep: normalizeStartStep(tiny.startStep, fallbackTitle: tiny.title),
                    estimateMinutes: min(tiny.estimateMinutes, 5),
                    reminderId: nil,
                    inboxId: tiny.id,
                    focusSessionId: nil
                )
            )
        }

        // B3) Most recent inbox item (fallback, if different)
        if let recent = inboxItems.first,
           out.first(where: { $0.inboxId == recent.id }) == nil
        {
            out.append(
                StuckSuggestion(
                    source: .inbox,
                    title: recent.title,
                    startStep: normalizeStartStep(recent.startStep, fallbackTitle: recent.title),
                    estimateMinutes: min(recent.estimateMinutes, 5),
                    reminderId: nil,
                    inboxId: recent.id,
                    focusSessionId: nil
                )
            )
        }

        // If nothing at all, return an empty list.
        return out
    }

    private static func nextSoonReminder(reminders: [VerboseReminder], now: Date, hours: Int) -> VerboseReminder? {
        let windowEnd = now.addingTimeInterval(TimeInterval(hours * 3600))
        // You already sort reminders ascending in TodayView, but we don’t assume that here.
        return reminders
            .filter { !$0.isDone && $0.scheduledAt >= now && $0.scheduledAt <= windowEnd }
            .sorted(by: { $0.scheduledAt < $1.scheduledAt })
            .first
    }

    static func normalizeStartStep(_ step: String, fallbackTitle: String) -> String {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        // Simple heuristic fallbacks (rule-based, no AI)
        let lower = fallbackTitle.lowercased()
        if lower.contains("email") { return "Open Mail and draft one sentence." }
        if lower.contains("text") || lower.contains("message") { return "Open Messages and type one sentence." }
        if lower.contains("call") { return "Open Phone and find the number." }
        if lower.contains("pay") { return "Open the bill and locate the amount due." }
        if lower.contains("schedule") { return "Open your calendar and pick a time." }

        return "Open what you need and do the smallest possible step for 2 minutes."
    }

    static func makeEvenSmaller(_ currentStep: String) -> String {
        // MVP: one consistent, safe shrink
        return "Only open what you need. One click is enough."
    }
}
