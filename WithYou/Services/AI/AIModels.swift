//
//  AIModels.swift
//  WithYou
//
//  Plain value types shared by the AI layer and the features that use it.
//  They are `nonisolated` so they can be built, compared and passed anywhere
//  (Siri intents, background work, tests) without hopping to the main actor.
//

import Foundation
import SwiftData

/// Where a suggestion came from. Features show a small attribution for `.onDevice`
/// and `.cloud`, and nothing for `.rules`.
nonisolated enum AISource: String {
    case onDevice, cloud, rules
}

nonisolated struct AIResult<Value> {
    let value: Value
    let source: AISource
}

// MARK: - Capture

/// What "now" means for a capture: the person's local time and their profile's hours.
nonisolated struct CaptureContext {
    var now: Date
    var timeZone: TimeZone
    var morningHour: Int   // from the active UserProfile, default 9
    var eveningHour: Int   // default 19

    static let defaultMorningHour = 9
    static let defaultEveningHour = 19

    /// The current time in this device's time zone, with the active profile's hours.
    @MainActor
    static func current(profile: UserProfile?) -> CaptureContext {
        CaptureContext(
            now: Date(),
            timeZone: .current,
            morningHour: validHour(profile?.morningHour, default: defaultMorningHour),
            eveningHour: validHour(profile?.eveningHour, default: defaultEveningHour)
        )
    }

    private static func validHour(_ hour: Int?, default fallback: Int) -> Int {
        guard let hour else { return fallback }
        return min(max(hour, 0), 23)
    }
}

/// One item the person can review before it is saved.
nonisolated struct CaptureSuggestion: Identifiable, Equatable {
    let id: UUID
    var title: String
    var firstStep: String
    var estimateMinutes: Int
    var scheduledAt: Date?       // nil → Inbox; non-nil → scheduled reminder
    var originalText: String     // the source text this item came from (stored as InboxItem.content)

    init(
        id: UUID = UUID(),
        title: String,
        firstStep: String,
        estimateMinutes: Int,
        scheduledAt: Date? = nil,
        originalText: String
    ) {
        self.id = id
        self.title = title
        self.firstStep = firstStep
        self.estimateMinutes = estimateMinutes
        self.scheduledAt = scheduledAt
        self.originalText = originalText
    }
}

// MARK: - Stuck

nonisolated enum StuckBlocker: String, CaseIterable, Identifiable {
    case dontKnowWhereToStart = "dont_know_where_to_start"
    case tooBig = "too_big"
    case boring = "boring"
    case worried = "worried"
    case lowEnergy = "low_energy"
    case distracted = "distracted"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dontKnowWhereToStart: return "I don’t know where to start"
        case .tooBig: return "It feels too big"
        case .boring: return "It’s boring"
        case .worried: return "I’m worried about it"
        case .lowEnergy: return "I’m low on energy"
        case .distracted: return "I keep getting distracted"
        }
    }
}

nonisolated struct StuckSuggestion: Equatable {
    var message: String
    var step: String
    var minutes: Int
}

// MARK: - Next

nonisolated struct NextCandidate: Equatable {
    var id: String               // e.g. InboxItem.id.uuidString or VerboseReminder.id.uuidString
    var title: String
    var estimateMinutes: Int?
    var scheduledAt: Date?
}

nonisolated struct NextSuggestion: Equatable {
    var candidateId: String
    var reason: String
    var firstStep: String
}

// MARK: - Tidy

nonisolated struct TidyItem: Equatable {
    var title: String
    var firstStep: String
}
