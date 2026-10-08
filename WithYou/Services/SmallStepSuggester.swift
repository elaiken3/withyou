//
//  SmallStepSuggester.swift
//  WithYou
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Suggests a smaller first step for "Make it smaller".
///
/// On devices with Apple Intelligence (iOS 26+), the on-device model writes a step
/// specific to the task. Nothing leaves the device. Everywhere else, and whenever the
/// model is unavailable or slow, it falls back to simple rules.
enum SmallStepSuggester {
    static let genericStep = "Open what you need and do the smallest possible step for 2 minutes."

    /// Returns a smaller step than `current` for a task titled `title`.
    static func smallerStep(for title: String, current: String) async -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if let suggestion = await modelSuggestion(for: title, current: current) {
                return suggestion
            }
        }
        #endif
        return ruleBasedStep(for: title, current: current)
    }

    /// Instant, offline fallback. Never returns the same text as `current`.
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
}

#if canImport(FoundationModels)
@available(iOS 26.0, *)
extension SmallStepSuggester {
    fileprivate static func modelSuggestion(for title: String, current: String) async -> String? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(instructions: """
            You help a person with ADHD start a task. Reply with one tiny, concrete first \
            action that takes under two minutes. Start with a verb. Use at most 12 words. \
            No preamble, no quotes, no lists, and no pressure or judgment.
            """)

        do {
            let prompt = "Task: \(title)\nCurrent first step: \(current)\nA smaller first step:"
            let response = try await session.respond(to: prompt)
            let text = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”'"))
            guard !text.isEmpty, text.count <= 120, !text.contains("\n") else { return nil }
            return text
        } catch {
            return nil
        }
    }
}
#endif
