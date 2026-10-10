//
//  BreathPhaseTracker.swift
//  WithYou
//
//  Decides what Refocus does when the breath reaches a new phase: each phase runs once,
//  the finish runs once, and a stale moment never sends it backwards.
//  Pure value types, safe to use from any thread.
//

import Foundation

/// What Refocus does for a phase it hasn't handled yet.
nonisolated enum BreathPhaseEvent: Equatable, Sendable {
    /// A new phase began: show and announce `word`, and play `curve` if haptics are on.
    case phase(word: String, curve: BreathHapticCurve)
    /// The session just ended.
    case finished
}

/// Remembers the last phase Refocus handled, so the words, haptic and announcement for
/// each phase (and the finish) run exactly once per session.
nonisolated struct BreathPhaseTracker: Equatable, Sendable {
    /// The last phase index already handled; -1 before the first phase.
    private(set) var handledIndex = -1

    init() {}

    /// Starts over for a fresh session (on open, "Again" and a new pattern).
    mutating func reset() {
        handledIndex = -1
    }

    /// The event for `state`, or nil when its phase (or a later one) was already handled.
    /// - Parameter runCount: how many times "Again" was chosen, so a new run doesn't
    ///   start with the same words as the last one.
    mutating func advance(to state: BreathState, runCount: Int) -> BreathPhaseEvent? {
        // A stale frame can briefly report an earlier phase; only ever move forward.
        guard state.phaseIndex > handledIndex else { return nil }
        handledIndex = state.phaseIndex

        if state.isFinished { return .finished }

        // Rotating by occurrence (and by run, for "Again") never repeats the previous phrase.
        let word = BreathWords.word(for: state.phase.kind, occurrence: state.occurrence + runCount)
        return .phase(word: word, curve: BreathHapticCurve(state: state))
    }
}
