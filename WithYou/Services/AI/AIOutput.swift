//
//  AIOutput.swift
//  WithYou
//
//  Checks and tidies whatever a model returns before anyone sees it: plain one-line text,
//  sensible lengths and numbers, dates worked out on this device. Both the on-device model
//  and cloud AI go through here, so every feature gets the same guarantees.
//

import Foundation

/// A capture item as a model returns it, before it is checked.
/// Cloud AI decodes it straight from the API's JSON.
nonisolated struct AICaptureDraft: Decodable, Equatable {
    var title: String
    var firstStep: String
    var estimateMinutes: Int
    var when: CaptureWhen?

    enum CodingKeys: String, CodingKey {
        case title
        case firstStep = "first_step"
        case estimateMinutes = "estimate_minutes"
        case when
    }
}

/// "When" relative to the capture's local date: `dayOffset` 0 is today, 1 is tomorrow.
nonisolated struct CaptureWhen: Decodable, Equatable {
    var dayOffset: Int
    var hour: Int
    var minute: Int

    enum CodingKeys: String, CodingKey {
        case dayOffset = "day_offset"
        case hour
        case minute
    }
}

enum AIOutput {
    static let maxCaptureItems = 12
    static let maxCaptureTextLength = 4000
    static let maxTitleLength = 80
    static let maxStepLength = 100
    static let maxMessageLength = 160
    static let maxReasonLength = 120
    static let estimateRange = 1...240
    static let stuckMinutesRange = 1...10
    static let breakDownStepRange = 2...5
    static let maxCandidates = 30
    static let maxThoughts = 30

    // MARK: - Text

    /// One line of plain text: no markdown markers, list bullets or wrapping quotes,
    /// whitespace collapsed, and at most `maxLength` characters (cut at a word when one is close).
    static func cleanText(_ raw: String, maxLength: Int) -> String {
        var text = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        text = stripBullet(text)
        text = stripWrappingQuotes(text)

        guard text.count > maxLength else { return text }
        var cut = String(text.prefix(maxLength))
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= maxLength * 2 / 3 {
            cut = String(cut[..<space])
        }
        return cut.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-–—"))
    }

    /// Removes a leading list marker ("- ", "• ", "1. ", "2) ", "[ ] ").
    static func stripBullet(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = bulletPrefix,
              let match = regex.firstMatch(in: trimmed, options: [], range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
              let range = Range(match.range, in: trimmed) else {
            return trimmed
        }
        return String(trimmed[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// At most `max` Unicode scalars, which is how the cloud API counts characters.
    static func limitScalars(_ text: String, to max: Int) -> String {
        guard text.unicodeScalars.count > max else { return text }
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.prefix(max))
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func stripWrappingQuotes(_ text: String) -> String {
        let pairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("'", "'"), ("‘", "’")]
        for (open, close) in pairs where text.count >= 2 && text.first == open && text.last == close {
            return String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static let bulletPrefix = try? NSRegularExpression(
        pattern: #"^(?:[-*•‣◦·>]+|\d{1,2}[.)]|\[[ xX]?\])\s+"#
    )

    // MARK: - Capture

    /// The date for a capture's "when", in the capture's time zone. A time that has already
    /// passed today moves to tomorrow, the same way `CaptureParser` treats "at 3pm" said at 5pm.
    static func scheduledDate(for when: CaptureWhen, context: CaptureContext) -> Date? {
        var calendar = Calendar.current
        calendar.timeZone = context.timeZone

        let dayOffset = clamp(when.dayOffset, to: 0...30)
        let hour = clamp(when.hour, to: 0...23)
        let minute = clamp(when.minute, to: 0...59)

        let today = calendar.startOfDay(for: context.now)
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today),
              let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
            return nil
        }
        if date > context.now { return date }
        return calendar.date(byAdding: .day, value: 1, to: date)
    }

    /// Checked suggestions for `text`, or nil when the model gave nothing usable.
    ///
    /// When the text is a list with exactly as many lines as items, each item keeps its own line
    /// as `originalText`; otherwise every item keeps the whole text.
    static func captureSuggestions(
        from drafts: [AICaptureDraft],
        text: String,
        context: CaptureContext
    ) -> [CaptureSuggestion]? {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = AIRules.captureLines(original)
        let matchesLines = lines.count > 1 && lines.count == drafts.count

        var suggestions: [CaptureSuggestion] = []
        for (index, draft) in drafts.enumerated() {
            var title = cleanText(draft.title, maxLength: maxTitleLength)
            // When items line up with lines, this item is the only one that carries its line,
            // so an empty title falls back to the line itself rather than dropping it.
            if title.isEmpty, matchesLines {
                title = cleanText(lines[index], maxLength: maxTitleLength)
            }
            guard !title.isEmpty else { continue }

            var step = cleanText(draft.firstStep, maxLength: maxStepLength)
            if step.isEmpty {
                step = SmallStepSuggester.ruleBasedStep(for: title, current: "")
            }

            suggestions.append(CaptureSuggestion(
                title: title,
                firstStep: step,
                estimateMinutes: clamp(draft.estimateMinutes, to: estimateRange),
                scheduledAt: draft.when.flatMap { scheduledDate(for: $0, context: context) },
                originalText: matchesLines ? lines[index] : original
            ))
            if suggestions.count == maxCaptureItems { break }
        }
        return suggestions.isEmpty ? nil : suggestions
    }

    // MARK: - Break down

    /// 2–5 distinct steps that don't repeat `currentStep`, or nil when there aren't enough.
    static func breakDownSteps(from raw: [String], currentStep: String) -> [String]? {
        let current = cleanText(currentStep, maxLength: maxStepLength).lowercased()
        var seen: Set<String> = []
        var steps: [String] = []
        for item in raw {
            let step = cleanText(item, maxLength: maxStepLength)
            let key = step.lowercased()
            guard !step.isEmpty, key != current, !seen.contains(key) else { continue }
            seen.insert(key)
            steps.append(step)
            if steps.count == breakDownStepRange.upperBound { break }
        }
        return steps.count >= breakDownStepRange.lowerBound ? steps : nil
    }

    // MARK: - Stuck

    static func stuckSuggestion(_ raw: StuckSuggestion) -> StuckSuggestion? {
        let message = cleanText(raw.message, maxLength: maxMessageLength)
        let step = cleanText(raw.step, maxLength: maxStepLength)
        guard !message.isEmpty, !step.isEmpty else { return nil }
        return StuckSuggestion(message: message, step: step, minutes: clamp(raw.minutes, to: stuckMinutesRange))
    }

    // MARK: - Next

    /// Candidates worth sending: a title, a unique id (up to 128 characters), at most 30.
    static func usableCandidates(_ candidates: [NextCandidate]) -> [NextCandidate] {
        var seen: Set<String> = []
        var result: [NextCandidate] = []
        for candidate in candidates {
            var cleaned = candidate
            cleaned.title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.id.isEmpty, cleaned.id.utf16.count <= 128,
                  !cleaned.title.isEmpty, !seen.contains(cleaned.id) else { continue }
            seen.insert(cleaned.id)
            result.append(cleaned)
            if result.count == maxCandidates { break }
        }
        return result
    }

    /// The model's pick, if it names one of `candidates` and gives a reason.
    static func nextSuggestion(_ raw: NextSuggestion, candidates: [NextCandidate]) -> NextSuggestion? {
        guard let candidate = candidates.first(where: { $0.id == raw.candidateId }) else { return nil }
        let reason = cleanText(raw.reason, maxLength: maxReasonLength)
        guard !reason.isEmpty else { return nil }
        var step = cleanText(raw.firstStep, maxLength: maxStepLength)
        if step.isEmpty {
            step = SmallStepSuggester.ruleBasedStep(for: candidate.title, current: "")
        }
        return NextSuggestion(candidateId: candidate.id, reason: reason, firstStep: step)
    }

    // MARK: - Tidy

    /// One item per thought, in order. Items the model left empty use `fallback` (same count).
    /// Nil when the model returned a different number of items, since they may not line up.
    static func tidyItems(_ raw: [TidyItem], fallback: [TidyItem]) -> [TidyItem]? {
        guard raw.count == fallback.count, !raw.isEmpty else { return nil }
        return zip(raw, fallback).map { pair -> TidyItem in
            let (item, rules) = pair
            let title = cleanText(item.title, maxLength: maxTitleLength)
            guard !title.isEmpty else { return rules }
            let step = cleanText(item.firstStep, maxLength: maxStepLength)
            return TidyItem(
                title: title,
                firstStep: step.isEmpty ? SmallStepSuggester.ruleBasedStep(for: title, current: "") : step
            )
        }
    }
}
