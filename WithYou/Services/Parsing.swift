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

final class CaptureParser {
    func parse(_ raw: String, profile: UserProfile?, now: Date = Date()) -> ParsedCapture {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = extractTitle(from: cleaned)
        let startStep = suggestStartStep(from: title)
        let estimate = suggestEstimateMinutes(from: title)

        let scheduledAt =
            detectDate(in: cleaned, now: now)
            ?? detectPartOfDay(in: cleaned, now: now, profile: profile)

        return ParsedCapture(title: title, startStep: startStep, estimateMinutes: estimate, scheduledAt: scheduledAt)
    }

    private func extractTitle(from s: String) -> String {
        var t = s
        let prefixes = [
            "remind me to ", "remind me ", "i need to ", "dont forget to ", "don't forget to ",
            "capture ", "note to "
        ]
        for p in prefixes {
            if t.lowercased().hasPrefix(p) {
                t = String(t.dropFirst(p.count))
                break
            }
        }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(80)).capitalizedSentence
    }

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

    private func detectDate(in text: String, now: Date) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = detector?.matches(in: text, options: [], range: range) ?? []
        return matches.first?.date
    }

    private func detectPartOfDay(in text: String, now: Date, profile: UserProfile?) -> Date? {
        let lower = text.lowercased()

        var base = now
        if lower.contains("tomorrow") {
            base = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        }

        let morning = profile?.morningHour ?? 9
        let afternoon = profile?.afternoonHour ?? 13
        let evening = profile?.eveningHour ?? 19

        if lower.contains("morning") { return setHour(morning, on: base) }
        if lower.contains("afternoon") { return setHour(afternoon, on: base) }
        if lower.contains("evening") || lower.contains("tonight") { return setHour(evening, on: base) }

        return nil
    }

    private func setHour(_ hour: Int, on date: Date) -> Date? {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        return Calendar.current.date(from: comps)
    }
}

private extension String {
    var capitalizedSentence: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}

