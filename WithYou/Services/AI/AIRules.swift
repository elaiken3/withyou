//
//  AIRules.swift
//  WithYou
//
//  The simple, offline answers every AI feature falls back to. They run instantly,
//  never leave the device, and are what people get when no model is available.
//

import Foundation
import SwiftData

enum AIRules {

    // MARK: - Capture

    /// The separate lines of a capture, with list bullets removed and blank lines dropped.
    static func captureLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { AIOutput.stripBullet($0) }
            .filter { !$0.isEmpty }
    }

    /// One item per line (or one item for a single line), parsed with `CaptureParser`.
    static func capture(_ text: String, context: CaptureContext) -> [CaptureSuggestion] {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = captureLines(original)
        guard !lines.isEmpty else { return [] }

        let parser = CaptureParser()
        let profile = parserProfile(for: context)

        if lines.count == 1 {
            let parsed = parser.parse(lines[0], profile: profile, now: context.now)
            return [suggestion(from: parsed, originalText: original)]
        }
        return lines.map { line in
            suggestion(from: parser.parse(line, profile: profile, now: context.now), originalText: line)
        }
    }

    private static func suggestion(from parsed: ParsedCapture, originalText: String) -> CaptureSuggestion {
        CaptureSuggestion(
            title: parsed.title,
            firstStep: parsed.startStep,
            estimateMinutes: AIOutput.clamp(parsed.estimateMinutes, to: AIOutput.estimateRange),
            scheduledAt: parsed.scheduledAt,
            originalText: originalText
        )
    }

    /// `CaptureParser` reads part-of-day hours from a profile. With the default hours it needs
    /// none; otherwise a temporary (never saved) profile carries the context's hours.
    private static func parserProfile(for context: CaptureContext) -> UserProfile? {
        if context.morningHour == CaptureContext.defaultMorningHour,
           context.eveningHour == CaptureContext.defaultEveningHour {
            return nil
        }
        // SwiftData needs a container that knows the model before an instance can be made.
        _ = AppModelContainer.shared
        return UserProfile(name: "", morningHour: context.morningHour, eveningHour: context.eveningHour)
    }

    // MARK: - Break down

    static func breakDown(title: String, currentStep: String) -> [String] {
        SmallStepSuggester.ruleBasedSteps(for: title, current: currentStep)
    }

    // MARK: - Stuck

    static func stuckHelp(title: String, blocker: StuckBlocker, energy: EnergyLevel?) -> StuckSuggestion {
        var suggestion: StuckSuggestion
        switch blocker {
        case .dontKnowWhereToStart:
            suggestion = StuckSuggestion(
                message: "Not knowing where to start is really common. You only need the very first step.",
                step: SmallStepSuggester.ruleBasedStep(for: title, current: ""),
                minutes: 2
            )
        case .tooBig:
            suggestion = StuckSuggestion(
                message: "It makes sense that it feels big. Let’s look at just one small piece.",
                step: "Write down the first small piece. Nothing else yet.",
                minutes: 3
            )
        case .boring:
            suggestion = StuckSuggestion(
                message: "Boring things are genuinely hard to start. A short, set time can help.",
                step: "Put on something you like and do it until the timer ends.",
                minutes: 5
            )
        case .worried:
            suggestion = StuckSuggestion(
                message: "It’s okay to feel uneasy about this. Naming the worry can make it lighter.",
                step: "Write one sentence about what worries you.",
                minutes: 3
            )
        case .lowEnergy:
            suggestion = StuckSuggestion(
                message: "Low energy is real, and a tiny step still counts.",
                step: "Do the easiest part for 2 minutes. Sitting down is fine.",
                minutes: 2
            )
        case .distracted:
            suggestion = StuckSuggestion(
                message: "Your attention is being pulled in a lot of directions. That’s okay.",
                step: "Close other apps and tabs, then do one small part.",
                minutes: 5
            )
        }
        if energy == .low {
            suggestion.minutes = min(suggestion.minutes, 2)
        }
        return suggestion
    }

    // MARK: - Next

    /// Low energy → the smallest estimate; otherwise the soonest scheduled; otherwise the first.
    /// With `minutesAvailable`, things that fit in that time come first. Nil without candidates.
    static func suggestNext(
        from candidates: [NextCandidate],
        energy: EnergyLevel?,
        minutesAvailable: Int?
    ) -> NextSuggestion? {
        let usable = AIOutput.usableCandidates(candidates)
        guard let first = usable.first else { return nil }

        var pool = usable
        var fitsTime = false
        if let minutesAvailable {
            let fitting = usable.filter { ($0.estimateMinutes ?? 0) <= minutesAvailable }
            if !fitting.isEmpty {
                pool = fitting
                fitsTime = fitting.count < usable.count
            }
        }

        if energy == .low,
           let smallest = pool.filter({ $0.estimateMinutes != nil })
               .min(by: { ($0.estimateMinutes ?? 0) < ($1.estimateMinutes ?? 0) }) {
            return suggestion(for: smallest, reason: "It’s one of the smallest things here, which suits a low-energy moment.")
        }

        if let soonest = pool.filter({ $0.scheduledAt != nil })
            .min(by: { ($0.scheduledAt ?? .distantFuture) < ($1.scheduledAt ?? .distantFuture) }) {
            return suggestion(for: soonest, reason: "It’s the next thing on your plan.")
        }

        if fitsTime, let fitting = pool.first {
            return suggestion(for: fitting, reason: "It fits in the time you have.")
        }
        return suggestion(for: first, reason: "It’s first on your list.")
    }

    private static func suggestion(for candidate: NextCandidate, reason: String) -> NextSuggestion {
        NextSuggestion(
            candidateId: candidate.id,
            reason: reason,
            firstStep: SmallStepSuggester.ruleBasedStep(for: candidate.title, current: "")
        )
    }

    // MARK: - Tidy

    static let tidyPlaceholderTitle = "A thought from focus"

    /// Each thought, trimmed, as its own title with a simple first step. Same count and order.
    static func tidy(_ thoughts: [String]) -> [TidyItem] {
        thoughts.map { thought -> TidyItem in
            var title = AIOutput.cleanText(thought, maxLength: AIOutput.maxTitleLength)
            if title.isEmpty {
                title = tidyPlaceholderTitle
            } else if let first = title.first, first.isLowercase {
                title = first.uppercased() + title.dropFirst()
            }
            return TidyItem(title: title, firstStep: SmallStepSuggester.ruleBasedStep(for: title, current: ""))
        }
    }
}
