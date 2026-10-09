//
//  BreathPattern.swift
//  WithYou
//
//  The breathing rhythms Refocus offers. Pure data, safe to use from any thread.
//

import Foundation

/// One part of a breath.
nonisolated enum BreathPhaseKind: String, Codable, CaseIterable, Sendable {
    case inhale
    case hold
    case exhale
    /// A short second sip of air on top of a full inhale (the physiological sigh).
    case topUp
}

/// A phase of a pattern: what to do, for how long, and how full the breath is when it ends.
nonisolated struct BreathPhase: Equatable, Sendable {
    let kind: BreathPhaseKind
    let seconds: Double
    /// 0 is empty, 1 is full. A phase starts where the previous one ended.
    let endLevel: Double
}

/// A breathing rhythm. Stored in AppStorage (`refocusPattern`) by its raw value,
/// so the raw values must never change.
nonisolated enum BreathPattern: String, Codable, CaseIterable, Identifiable, Sendable {
    /// In 4, out 4. The original Refocus rhythm and the default.
    case calm
    /// In 4, hold 4, out 4, hold 4.
    case box
    /// In 4, hold 7, out 8.
    case fourSevenEight
    /// In 2, a short top-up of 1, then a long 6-second out.
    case sigh

    var id: String { rawValue }

    /// About how long one Refocus lasts. Sessions are always whole breaths.
    static let targetSessionSeconds: Double = 60

    var title: String {
        switch self {
        case .calm: return "Calm"
        case .box: return "Box"
        case .fourSevenEight: return "4-7-8"
        case .sigh: return "Sigh"
        }
    }

    /// The rhythm in a few words, e.g. "in 4, out 4".
    var detail: String {
        switch self {
        case .calm: return "in 4, out 4"
        case .box: return "in 4, hold 4, out 4, hold 4"
        case .fourSevenEight: return "in 4, hold 7, out 8"
        case .sigh: return "in 2, a little more, out 6"
        }
    }

    /// "Calm — in 4, out 4", for the pattern menu.
    var menuTitle: String {
        "\(title) — \(detail)"
    }

    /// One breath, in order. Every pattern starts with an inhale and ends empty,
    /// so breaths join up smoothly.
    var phases: [BreathPhase] {
        switch self {
        case .calm:
            return [
                BreathPhase(kind: .inhale, seconds: 4, endLevel: 1),
                BreathPhase(kind: .exhale, seconds: 4, endLevel: 0)
            ]
        case .box:
            return [
                BreathPhase(kind: .inhale, seconds: 4, endLevel: 1),
                BreathPhase(kind: .hold, seconds: 4, endLevel: 1),
                BreathPhase(kind: .exhale, seconds: 4, endLevel: 0),
                BreathPhase(kind: .hold, seconds: 4, endLevel: 0)
            ]
        case .fourSevenEight:
            return [
                BreathPhase(kind: .inhale, seconds: 4, endLevel: 1),
                BreathPhase(kind: .hold, seconds: 7, endLevel: 1),
                BreathPhase(kind: .exhale, seconds: 8, endLevel: 0)
            ]
        case .sigh:
            return [
                BreathPhase(kind: .inhale, seconds: 2, endLevel: 0.8),
                BreathPhase(kind: .topUp, seconds: 1, endLevel: 1),
                BreathPhase(kind: .exhale, seconds: 6, endLevel: 0)
            ]
        }
    }

    /// Seconds in one breath.
    var cycleSeconds: Double {
        phases.reduce(0) { $0 + $1.seconds }
    }

    /// Whole breaths closest to `targetSessionSeconds` (never fewer than one).
    var defaultCycles: Int {
        max(1, Int((Self.targetSessionSeconds / cycleSeconds).rounded()))
    }

    /// How full the breath is when the phase at `index` begins.
    func startLevel(ofPhaseAt index: Int) -> Double {
        let phases = self.phases
        guard index > 0, index < phases.count else { return phases[phases.count - 1].endLevel }
        return phases[index - 1].endLevel
    }
}

/// The words Refocus shows (and VoiceOver reads) for each phase. They rotate so the
/// same phrase never shows twice in a row for the same kind of phase.
nonisolated enum BreathWords {
    static let inhale = ["Breathe in", "In, slowly", "Fill up gently", "Let the air in"]
    static let exhale = ["Breathe out", "Let it go", "Slowly out", "Soften your shoulders"]
    static let hold = ["Hold gently", "Rest here", "A soft pause", "Stay soft"]
    static let topUp = ["A little more", "Top it up", "One more sip of air", "Just a bit more"]

    static func phrases(for kind: BreathPhaseKind) -> [String] {
        switch kind {
        case .inhale: return inhale
        case .hold: return hold
        case .exhale: return exhale
        case .topUp: return topUp
        }
    }

    /// The phrase for the `occurrence`-th phase of this kind (0 is the first).
    static func word(for kind: BreathPhaseKind, occurrence: Int) -> String {
        let words = phrases(for: kind)
        let count = words.count
        let index = ((occurrence % count) + count) % count
        return words[index]
    }
}
