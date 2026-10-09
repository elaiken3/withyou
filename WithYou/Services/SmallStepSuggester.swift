//
//  SmallStepSuggester.swift
//  WithYou
//

import Foundation

/// Simple, offline small steps. The rules behind "Break it down" and the first steps the
/// AI layer falls back to (see `AIRules`); model-written steps go through `AIService`.
enum SmallStepSuggester {
    static let genericStep = "Open what you need and do the smallest possible step for 2 minutes."

    /// One small first step for a task titled `title`. Never returns the same text as `current`.
    static func ruleBasedStep(for title: String, current: String) -> String {
        let lower = title.lowercased()
        let candidates: [String]

        if lower.contains("email") || lower.contains("reply") {
            candidates = ["Open Mail and find the thread.", "Write just the first sentence."]
        } else if lower.contains("text") || lower.contains("message") {
            candidates = ["Open Messages and find the chat.", "Type one sentence. Don’t send yet."]
        } else if lower.contains("call") || lower.contains("phone") {
            candidates = ["Find the phone number.", "Write down the one thing you need to ask."]
        } else if lower.contains("pay") || lower.contains("bill") || lower.contains("rent") {
            candidates = ["Open the bill and find the amount.", "Open the payment app. That’s all."]
        } else if lower.contains("clean") || lower.contains("tidy") || lower.contains("laundry") {
            candidates = ["Pick up five things.", "Set a 2-minute timer and start with one surface."]
        } else if lower.contains("write") || lower.contains("draft") || lower.contains("essay") {
            candidates = ["Open the document.", "Write one messy sentence."]
        } else if lower.contains("schedule") || lower.contains("appointment") || lower.contains("book") {
            candidates = ["Find the number or website.", "Open your calendar and pick a possible time."]
        } else {
            candidates = [genericStep, "Only open what you need. One click is enough."]
        }

        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.first(where: { $0 != trimmedCurrent }) ?? candidates[0]
    }

    /// Instant, offline steps for "Break it down": 2–4 tiny steps in order, the first one
    /// under 2 minutes. Leaves out `current` when there are enough steps without it.
    static func ruleBasedSteps(for title: String, current: String) -> [String] {
        let lower = title.lowercased()
        let steps: [String]

        if lower.contains("email") || lower.contains("reply") {
            steps = ["Open Mail and find the thread.", "Write just the first sentence.",
                     "Add the rest in plain words.", "Read it once, then send."]
        } else if lower.contains("text") || lower.contains("message") {
            steps = ["Open Messages and find the chat.", "Type one sentence. Don’t send yet.",
                     "Add anything else, then send."]
        } else if lower.contains("call") || lower.contains("phone") {
            steps = ["Find the phone number.", "Write down the one thing you need to ask.",
                     "Make the call. It’s fine to read from your note."]
        } else if lower.contains("pay") || lower.contains("bill") || lower.contains("rent") {
            steps = ["Open the bill and find the amount.", "Open the payment app or website.",
                     "Pay it and save the confirmation."]
        } else if lower.contains("clean") || lower.contains("tidy") || lower.contains("laundry") {
            steps = ["Pick up five things.", "Clear one surface.",
                     "Set a 5-minute timer and keep going until it ends."]
        } else if lower.contains("write") || lower.contains("draft") || lower.contains("essay") {
            steps = ["Open the document.", "Write one messy sentence.",
                     "Jot down three points that come next.", "Turn one point into a few sentences."]
        } else if lower.contains("schedule") || lower.contains("appointment") || lower.contains("book") {
            steps = ["Find the number or website.", "Open your calendar and pick a possible time.",
                     "Call or book online."]
        } else {
            steps = ["Open what you need.", "Do the smallest possible step for 2 minutes.",
                     "Pick the next small step, or stop there."]
        }

        let trimmedCurrent = current.trimmingCharacters(in: .whitespacesAndNewlines)
        let remaining = steps.filter { $0 != trimmedCurrent }
        return remaining.count >= 2 ? remaining : steps
    }
}
