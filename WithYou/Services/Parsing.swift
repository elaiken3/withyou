//
//  Parsing.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

struct ParsedCapture {
    let title: String
    let startStep: String
    let estimateMinutes: Int
    let scheduledAt: Date? // nil => Inbox
}

/// Turns a captured thought ("Email landlord tomorrow morning") into a title, a gentle
/// first step, and — only when a time is clearly mentioned — a date.
///
/// Scheduling rules (all relative to `now`, using `Calendar.current`):
/// - "tomorrow" / "day after tomorrow" / "today" / "tonight" pick the day. Otherwise a
///   date the detector found ("Friday", "Mar 12") picks it, and a bare time means today.
/// - An explicit clock time ("3pm", "15:30", "noon") always wins over part-of-day words.
/// - Part-of-day words without a clock time use the profile's hours
///   (morning 9, afternoon 13, evening 19 by default).
/// - A time that already passed today rolls forward a day ("at 3pm" said at 5pm means
///   tomorrow). If the person explicitly said today/tonight, it becomes "soon" instead.
/// - A day that has already gone by ("yesterday") is not scheduled: the thought goes to the Inbox.
final class CaptureParser {

    func parse(_ raw: String, profile: UserProfile?, now: Date = Date()) -> ParsedCapture {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateMatches = Self.dateMatches(in: cleaned)

        let title = makeTitle(from: cleaned, dateMatches: dateMatches)
        let startStep = suggestStartStep(from: title)
        let estimate = suggestEstimateMinutes(from: title)
        let scheduledAt = scheduledDate(in: cleaned, dateMatches: dateMatches, profile: profile, now: now)

        return ParsedCapture(title: title, startStep: startStep, estimateMinutes: estimate, scheduledAt: scheduledAt)
    }

    // MARK: - Title

    private func makeTitle(from cleaned: String, dateMatches: [NSTextCheckingResult]) -> String {
        let ns = cleaned as NSString
        var ranges: [NSRange] = []

        // Whatever the date detector recognised, plus a preposition in front of it ("on Friday").
        for match in dateMatches {
            ranges.append(Self.extendOverPreposition(match.range, in: ns))
        }

        // Standalone day / part-of-day words and clock times, even where the detector missed them.
        for pattern in Self.stripPatterns {
            ranges.append(contentsOf: Self.allMatches(pattern, in: cleaned).map { $0.range })
        }

        // "at 3" only counts as a time when the detector also saw a time there.
        for match in Self.allMatches(Self.bareAtHour, in: cleaned)
        where dateMatches.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            ranges.append(match.range)
        }

        let merged = Self.merge(ranges)
        let mutable = NSMutableString(string: cleaned)
        for range in merged.reversed() {
            mutable.replaceCharacters(in: range, with: " ")
        }

        var title = Self.collapseWhitespace(mutable as String)
        if !merged.isEmpty {
            title = Self.removeDanglingEnds(from: title)
        }
        title = Self.removeLeadingPhrases(from: title)
        title = Self.limited(title)

        if title.isEmpty {
            // Nothing but a time ("tomorrow morning"): keep the person's own words.
            title = Self.limited(Self.removeLeadingPhrases(from: Self.collapseWhitespace(cleaned)))
            if title.isEmpty {
                title = Self.limited(Self.collapseWhitespace(cleaned))
            }
        }

        return title.capitalizedSentence
    }

    private static let leadingPhrases = [
        "remind me to ", "remind me ", "remember to ",
        "don't forget to ", "don’t forget to ", "dont forget to ",
        "i need to ", "need to ", "i have to ", "i want to ",
        "note to self: ", "note to self ", "note to ",
        "todo: ", "to do: ", "capture "
    ]

    private static func removeLeadingPhrases(from text: String) -> String {
        var result = text
        // A couple of passes handles "Remind me, don't forget to …" style stacking.
        for _ in 0..<3 {
            let lower = result.lowercased()
            guard let phrase = leadingPhrases.first(where: { lower.hasPrefix($0) }) else { break }
            result = String(result.dropFirst(phrase.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,:;-").union(.whitespacesAndNewlines))
        }
        return result
    }

    private static func removeDanglingEnds(from text: String) -> String {
        var result = text
        if let match = firstMatch(danglingEnd, in: result), let range = Range(match.range, in: result) {
            result.removeSubrange(range)
        }
        if let match = firstMatch(danglingStart, in: result), let range = Range(match.range, in: result) {
            result.removeSubrange(range)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapseWhitespace(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func limited(_ text: String) -> String {
        String(text.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Grows `range` backwards over "at / on / by / for / around / in" so "Call mom on Friday"
    /// doesn't become "Call mom on". "in" is skipped before today/tomorrow so "Check in tomorrow"
    /// keeps its "in".
    private static func extendOverPreposition(_ range: NSRange, in ns: NSString) -> NSRange {
        guard range.location != NSNotFound, range.location > 0 else { return range }
        let prefix = ns.substring(to: range.location)
        let matched = ns.substring(with: range).lowercased()
        let startsWithDayWord = ["today", "tonight", "tomorrow", "tmr", "yesterday"].contains { matched.hasPrefix($0) }
        let pattern = startsWithDayWord ? trailingPrepositionWithoutIn : trailingPreposition
        guard let match = firstMatch(pattern, in: prefix) else { return range }
        let start = match.range.location
        return NSRange(location: start, length: range.location + range.length - start)
    }

    private static func merge(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in sorted {
            if let last = merged.last, range.location <= last.location + last.length {
                let end = max(last.location + last.length, range.location + range.length)
                merged[merged.count - 1] = NSRange(location: last.location, length: end - last.location)
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    // MARK: - First step and estimate

    private func suggestStartStep(from title: String) -> String {
        let lower = title.lowercased()

        if lower.hasPrefix("email ") || lower.contains(" email ") {
            return "Open Mail → find the thread → write 2 sentences"
        }
        if lower.hasPrefix("call ") || lower.contains(" call ") {
            return "Open Phone → search contact → tap call"
        }
        if lower.contains("pay ") || lower.contains(" bill") || lower.contains("rent") {
            return "Open the app/site → pay minimum/amount → confirm"
        }
        if lower.contains("schedule") || lower.contains("appointment") {
            return "Open Phone → call office → ask next available"
        }
        if lower.contains("buy ") || lower.contains("pick up ") {
            return "Add it to your shopping list / cart"
        }
        return "Open the first app you’ll use → do the smallest next step"
    }

    private func suggestEstimateMinutes(from title: String) -> Int {
        let lower = title.lowercased()
        if lower.contains("pay") { return 5 }
        if lower.contains("email") { return 4 }
        if lower.contains("call") { return 6 }
        if lower.contains("buy") { return 3 }
        return 5
    }

    // MARK: - Date

    private enum PartOfDay {
        case morning, afternoon, evening
    }

    private struct Clock {
        var hour: Int
        var minute: Int
        /// "midnight" means the very end of the chosen day.
        var isMidnight = false
    }

    /// Where the day came from, which decides what happens when the time already passed.
    private enum DayAnchor {
        /// No day mentioned ("at 3pm", "in the morning"): today, or tomorrow if it passed.
        case implied
        /// "today", "tonight", "this evening".
        case namedToday
        /// "tomorrow", "day after tomorrow".
        case namedFutureDay
        /// A date the detector found ("Friday", "Mar 12").
        case detectedDay(isWeekday: Bool)
    }

    private func scheduledDate(
        in text: String,
        dateMatches: [NSTextCheckingResult],
        profile: UserProfile?,
        now: Date
    ) -> Date? {
        guard !text.isEmpty else { return nil }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)

        // "in 20 minutes", "in an hour" are measured from now.
        if let offset = Self.relativeOffset(in: text) {
            return now.addingTimeInterval(offset)
        }

        let part = Self.partOfDay(in: text)
        let clock = Self.clockTime(in: text, part: part, dateMatches: dateMatches)
        let detected = dateMatches.first
        let detectedText = detected.map { (text as NSString).substring(with: $0.range) } ?? ""

        // 1. Which day?
        let day: Date
        let anchor: DayAnchor
        if Self.contains(Self.yesterdayWord, text) {
            return nil
        } else if Self.contains(Self.dayAfterTomorrowWord, text) {
            day = calendar.date(byAdding: .day, value: 2, to: today) ?? today
            anchor = .namedFutureDay
        } else if Self.contains(Self.tomorrowWord, text) {
            day = calendar.date(byAdding: .day, value: 1, to: today) ?? today
            anchor = .namedFutureDay
        } else if Self.contains(Self.todayWord, text) {
            day = today
            anchor = .namedToday
        } else if let date = detected?.date, Self.contains(Self.datePart, detectedText) {
            day = calendar.startOfDay(for: date)
            anchor = .detectedDay(isWeekday: Self.contains(Self.weekdayName, detectedText))
        } else if clock != nil || part != nil {
            day = today
            anchor = .implied
        } else if let date = detected?.date {
            // Something the rules above don't cover ("half past four"): trust the detector,
            // but never schedule into the past.
            return date > now ? date : nil
        } else {
            return nil
        }

        // A day that has already gone by is not scheduled; the thought goes to the Inbox.
        guard day >= today else { return nil }

        // 2. What time?
        let candidate: Date?
        if let clock {
            if clock.isMidnight {
                candidate = calendar.date(byAdding: .day, value: 1, to: day)
            } else {
                candidate = calendar.date(bySettingHour: clock.hour, minute: clock.minute, second: 0, of: day)
            }
        } else if let part {
            candidate = calendar.date(bySettingHour: Self.hour(for: part, profile: profile), minute: 0, second: 0, of: day)
        } else if let date = detected?.date, Self.contains(Self.detectorTimeHint, detectedText) {
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            candidate = calendar.date(bySettingHour: parts.hour ?? 9, minute: parts.minute ?? 0, second: 0, of: day)
        } else if case .namedToday = anchor {
            // "Call mom today": the next part of the day that hasn't happened yet.
            return Self.nextSlotToday(profile: profile, now: now)
        } else {
            // A day without a time ("tomorrow", "Friday"): the profile's morning.
            candidate = calendar.date(bySettingHour: Self.hour(for: .morning, profile: profile), minute: 0, second: 0, of: day)
        }

        guard let candidate else { return nil }
        if candidate > now { return candidate }

        // 3. The time already passed today.
        switch anchor {
        case .implied:
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        case .detectedDay(let isWeekday):
            return calendar.date(byAdding: .day, value: isWeekday ? 7 : 1, to: candidate)
        case .namedToday, .namedFutureDay:
            return Self.soon(after: now)
        }
    }

    private static func partOfDay(in text: String) -> PartOfDay? {
        if contains(eveningWord, text) { return .evening }
        if contains(afternoonWord, text) { return .afternoon }
        if contains(morningWord, text) { return .morning }
        return nil
    }

    private static func hour(for part: PartOfDay, profile: UserProfile?) -> Int {
        let hour: Int
        switch part {
        case .morning: hour = profile?.morningHour ?? 9
        case .afternoon: hour = profile?.afternoonHour ?? 13
        case .evening: hour = profile?.eveningHour ?? 19
        }
        return min(max(hour, 0), 23)
    }

    private static func clockTime(in text: String, part: PartOfDay?, dateMatches: [NSTextCheckingResult]) -> Clock? {
        // "3pm", "3:30 pm", "11 a.m."
        if let match = firstMatch(amPmTime, in: text),
           let hour = group(match, 1, in: text).flatMap({ Int($0) }),
           let marker = group(match, 3, in: text)?.lowercased() {
            let minute = group(match, 2, in: text).flatMap({ Int($0) }) ?? 0
            if (1...12).contains(hour), (0...59).contains(minute) {
                let isPM = marker == "p"
                let hour24 = isPM ? (hour == 12 ? 12 : hour + 12) : (hour == 12 ? 0 : hour)
                return Clock(hour: hour24, minute: minute)
            }
        }

        if contains(noonWord, text) { return Clock(hour: 12, minute: 0) }
        if contains(midnightWord, text) { return Clock(hour: 0, minute: 0, isMidnight: true) }

        // "15:30" (24-hour) or "3:30" (ambiguous).
        if let match = firstMatch(colonTime, in: text),
           let hour = group(match, 1, in: text).flatMap({ Int($0) }),
           let minute = group(match, 2, in: text).flatMap({ Int($0) }),
           (0...59).contains(minute) {
            if hour == 0 || (13...23).contains(hour) { return Clock(hour: hour, minute: minute) }
            if (1...12).contains(hour) { return resolveAmbiguous(hour: hour, minute: minute, part: part) }
        }

        // "4 o'clock"
        if let match = firstMatch(oClockTime, in: text),
           let hour = group(match, 1, in: text).flatMap({ Int($0) }),
           (1...12).contains(hour) {
            return resolveAmbiguous(hour: hour, minute: 0, part: part)
        }

        // "at 3" — only when the date detector also read a time there.
        for match in allMatches(bareAtHour, in: text)
        where dateMatches.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
            guard let hour = group(match, 1, in: text).flatMap({ Int($0) }) else { continue }
            if (1...12).contains(hour) { return resolveAmbiguous(hour: hour, minute: 0, part: part) }
            if hour == 0 || (13...23).contains(hour) { return Clock(hour: hour, minute: 0) }
        }

        return nil
    }

    /// A 1–12 hour with no am/pm: "tonight at 8" is 8 PM; otherwise 1–6 read as afternoon.
    private static func resolveAmbiguous(hour: Int, minute: Int, part: PartOfDay?) -> Clock {
        switch part {
        case .afternoon?, .evening?:
            return Clock(hour: hour == 12 ? 12 : hour + 12, minute: minute)
        case .morning?:
            return Clock(hour: hour, minute: minute)
        case nil:
            return Clock(hour: (1...6).contains(hour) ? hour + 12 : hour, minute: minute)
        }
    }

    private static func relativeOffset(in text: String) -> TimeInterval? {
        guard let match = firstMatch(relativeOffsetPattern, in: text),
              let unit = group(match, 4, in: text)?.lowercased() else { return nil }

        let amount: Double
        if let number = group(match, 1, in: text).flatMap({ Double($0) }) {
            amount = number
        } else if group(match, 3, in: text) != nil {
            amount = 0.5 // "in half an hour"
        } else {
            amount = 1 // "in an hour", "in a minute"
        }
        guard amount > 0 else { return nil }
        return amount * (unit.hasPrefix("h") ? 3600 : 60)
    }

    /// The next of the profile's morning / afternoon / evening hours that is still ahead today.
    private static func nextSlotToday(profile: UserProfile?, now: Date) -> Date {
        let calendar = Calendar.current
        let hours = [PartOfDay.morning, .afternoon, .evening].map { hour(for: $0, profile: profile) }.sorted()
        for hour in hours {
            if let slot = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now), slot > now {
                return slot
            }
        }
        return soon(after: now)
    }

    /// About half an hour from now, on a 5-minute mark.
    private static func soon(after now: Date) -> Date {
        let calendar = Calendar.current
        let target = now.addingTimeInterval(30 * 60)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: target)
        let floored = calendar.date(from: parts) ?? target
        let remainder = (parts.minute ?? 0) % 5
        return remainder == 0 ? floored : floored.addingTimeInterval(TimeInterval((5 - remainder) * 60))
    }

    // MARK: - Matching helpers

    /// Created once: building a data detector is expensive.
    private static let detector: NSDataDetector? = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.date.rawValue
    )

    private static func dateMatches(in text: String) -> [NSTextCheckingResult] {
        guard let detector = Self.detector, !text.isEmpty else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector.matches(in: text, options: [], range: range).filter { $0.date != nil }
    }

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private static func firstMatch(_ regex: NSRegularExpression?, in text: String) -> NSTextCheckingResult? {
        guard let regex, !text.isEmpty else { return nil }
        return regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    private static func allMatches(_ regex: NSRegularExpression?, in text: String) -> [NSTextCheckingResult] {
        guard let regex, !text.isEmpty else { return [] }
        return regex.matches(in: text, options: [], range: NSRange(text.startIndex..<text.endIndex, in: text))
    }

    private static func contains(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        firstMatch(regex, in: text) != nil
    }

    private static func group(_ match: NSTextCheckingResult, _ index: Int, in text: String) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let nsRange = match.range(at: index)
        guard nsRange.location != NSNotFound, let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }

    // MARK: - Patterns (case-insensitive)

    // Clock times
    private static let amPmTime = regex(#"\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?(?![a-z])"#)
    private static let colonTime = regex(#"\b(\d{1,2}):(\d{2})\b"#)
    private static let oClockTime = regex(#"\b(\d{1,2})\s*o['’]?\s?clock\b"#)
    private static let noonWord = regex(#"\bnoon\b"#)
    private static let midnightWord = regex(#"\bmidnight\b"#)
    private static let bareAtHour = regex(#"(?:\bat\s+|@\s*)(\d{1,2})\b(?![:.]\d)"#)

    // Days
    private static let yesterdayWord = regex(#"\byesterday\b"#)
    private static let dayAfterTomorrowWord = regex(#"\bday\s+after\s+tomorrow\b"#)
    private static let tomorrowWord = regex(#"\b(?:tomorrow|tmrw|tmr)\b"#)
    private static let todayWord = regex(#"\b(?:today|tonight)\b|\bthis\s+(?:morning|afternoon|evening)\b"#)

    // Parts of the day
    private static let morningWord = regex(#"\bmorning\b"#)
    private static let afternoonWord = regex(#"\bafternoon\b"#)
    private static let eveningWord = regex(#"\b(?:evening|tonight)\b|\b(?:tomorrow|tmrw|tmr)\s+night\b"#)

    // "in 20 minutes", "in an hour", "in half an hour"
    private static let relativeOffsetPattern = regex(#"\bin\s+(?:(\d{1,3})|(an?)|(half\s+an))\s+(minutes?|mins?|hours?|hrs?)\b"#)

    /// Signs that the detector's match names a day, not just a time.
    private static let datePart = regex(
        #"\b(?:mon|tues?|wed|thu(?:rs?)?|fri|sat|sun)(?:day|nesday|sday|urday)?\b|\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*\b|\d{1,4}[/.\-]\d{1,2}|\b\d{1,2}(?:st|nd|rd|th)\b|\b(?:next|week|weekend|month|year|days?)\b"#
    )
    private static let weekdayName = regex(#"\b(?:mon|tues?|wed|thu(?:rs?)?|fri|sat|sun)(?:day|nesday|sday|urday)?\b"#)
    /// Times the clock patterns don't read, where the detector's own time is used.
    private static let detectorTimeHint = regex(#"\bhalf\s+past\b|\bquarter\s+(?:past|to)\b"#)

    // Title clean-up
    private static let stripPatterns: [NSRegularExpression?] = [
        regex(#"(?:\b(?:at|on|by|for)\s+)?(?:\bthe\s+)?\bday\s+after\s+tomorrow\b"#),
        regex(#"(?:\b(?:at|on|by|for|until)\s+)?\b(?:today|tonight|yesterday|(?:tomorrow|tmrw|tmr)(?:\s+night)?)\b"#),
        regex(#"(?:\b(?:at|on|by|for|this|in\s+the)\s+)?\b(?:morning|afternoon|evening)\b"#),
        regex(#"(?:\b(?:at|by|around)\s+|@\s*)?\b\d{1,2}(?::\d{2})?\s*[ap]\.?m\.?(?![a-z])"#),
        regex(#"(?:\b(?:at|by|around)\s+|@\s*)?\b\d{1,2}:\d{2}\b"#),
        regex(#"(?:\b(?:at|by|around)\s+)?\b\d{1,2}\s*o['’]?\s?clock\b"#),
        regex(#"(?:\b(?:at|by|around)\s+)?\b(?:noon|midnight)\b"#),
        regex(#"\bin\s+(?:\d{1,3}|an?|half\s+an)\s+(?:minutes?|mins?|hours?|hrs?)\b"#)
    ]
    private static let trailingPreposition = regex(#"\b(?:at|on|by|for|around|in)\s+$"#)
    private static let trailingPrepositionWithoutIn = regex(#"\b(?:at|on|by|for|around)\s+$"#)
    /// Left behind after removing a time: "Call mom at" → "Call mom". ("in" is left alone so
    /// "Sign in" and "Check in" survive.)
    private static let danglingEnd = regex(#"(?:\s+(?:at|on|by|for|around)|[\s,.;:!?\-–—])+$"#)
    private static let danglingStart = regex(#"^[\s,.;:!?\-–—]+"#)
}

private extension String {
    var capitalizedSentence: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
