//
//  BreathEngine.swift
//  WithYou
//
//  One clock drives everything in Refocus: the orb, the words and the haptics all read
//  the same `BreathState` for a given moment. There are no timers, so nothing can drift.
//  Pure value types, safe to use from any thread.
//

import Foundation

/// Elapsed time that can be paused and resumed exactly (for example while the app is
/// in the background).
nonisolated struct BreathClock: Equatable, Sendable {
    private(set) var startDate: Date
    /// Total time spent paused in earlier pauses.
    private(set) var pausedDuration: TimeInterval = 0
    /// When the current pause began, if paused.
    private(set) var pausedAt: Date?

    init(startDate: Date) {
        self.startDate = startDate
    }

    var isPaused: Bool { pausedAt != nil }

    /// Freezes the clock at `date`. Pausing again while paused does nothing.
    mutating func pause(at date: Date) {
        guard pausedAt == nil else { return }
        pausedAt = date
    }

    /// Continues from exactly where the clock was paused. Does nothing if not paused.
    mutating func resume(at date: Date) {
        guard let start = pausedAt else { return }
        pausedDuration += max(0, date.timeIntervalSince(start))
        pausedAt = nil
    }

    /// Seconds that have counted so far (never negative).
    func elapsed(at date: Date) -> TimeInterval {
        var end = date
        if let pausedAt, pausedAt < date {
            end = pausedAt
        }
        return max(0, end.timeIntervalSince(startDate) - pausedDuration)
    }
}

/// Where the breath is at one moment.
nonisolated struct BreathState: Equatable, Sendable {
    /// The phase's position in the whole session: 0 is the first inhale. Once finished,
    /// this is one past the last phase, so a change always means something new to show.
    let phaseIndex: Int
    let phase: BreathPhase
    /// Which breath this is, from 0.
    let cycleIndex: Int
    /// How far through the phase, 0…1.
    let phaseProgress: Double
    /// How full the breath was when this phase began, 0…1.
    let phaseStartLevel: Double
    /// How full the breath is now, 0…1, eased so it moves smoothly across phase changes.
    let level: Double
    /// How many earlier phases of the same kind this session had (rotates the words).
    let occurrence: Int
    let elapsed: TimeInterval
    let remainingSeconds: TimeInterval
    let isFinished: Bool
}

/// A Refocus session: a pattern, a number of whole breaths and a pausable clock.
nonisolated struct BreathEngine: Equatable, Sendable {
    let pattern: BreathPattern
    let cycles: Int
    private(set) var clock: BreathClock

    /// - Parameter cycles: whole breaths; defaults to about a minute of the pattern.
    init(pattern: BreathPattern, cycles: Int? = nil, startDate: Date) {
        self.pattern = pattern
        self.cycles = max(1, cycles ?? pattern.defaultCycles)
        self.clock = BreathClock(startDate: startDate)
    }

    var totalDuration: TimeInterval {
        pattern.cycleSeconds * Double(cycles)
    }

    var isPaused: Bool { clock.isPaused }

    mutating func pause(at date: Date) {
        clock.pause(at: date)
    }

    mutating func resume(at date: Date) {
        clock.resume(at: date)
    }

    func state(at date: Date) -> BreathState {
        Self.state(pattern: pattern, cycles: cycles, elapsed: clock.elapsed(at: date))
    }

    /// The breath `elapsed` seconds into a session of `cycles` breaths of `pattern`.
    /// A moment exactly on a boundary belongs to the phase that starts there.
    static func state(pattern: BreathPattern, cycles: Int, elapsed: TimeInterval) -> BreathState {
        let phases = pattern.phases
        let cycles = max(1, cycles)
        let cycleLength = pattern.cycleSeconds
        let total = cycleLength * Double(cycles)
        let clamped = min(max(elapsed.isNaN ? 0 : elapsed, 0), total)

        if clamped >= total {
            let lastIndex = phases.count - 1
            let last = phases[lastIndex]
            return BreathState(
                phaseIndex: cycles * phases.count,
                phase: last,
                cycleIndex: cycles - 1,
                phaseProgress: 1,
                phaseStartLevel: pattern.startLevel(ofPhaseAt: lastIndex),
                level: last.endLevel,
                occurrence: occurrence(of: lastIndex, cycle: cycles - 1, in: phases),
                elapsed: total,
                remainingSeconds: 0,
                isFinished: true
            )
        }

        let cycle = min(Int(clamped / cycleLength), cycles - 1)
        var offset = clamped - Double(cycle) * cycleLength
        var index = 0
        while index < phases.count - 1, offset >= phases[index].seconds {
            offset -= phases[index].seconds
            index += 1
        }

        let phase = phases[index]
        let progress = phase.seconds > 0 ? min(max(offset / phase.seconds, 0), 1) : 1
        let startLevel = pattern.startLevel(ofPhaseAt: index)

        return BreathState(
            phaseIndex: cycle * phases.count + index,
            phase: phase,
            cycleIndex: cycle,
            phaseProgress: progress,
            phaseStartLevel: startLevel,
            level: level(from: startLevel, to: phase.endLevel, progress: progress),
            occurrence: occurrence(of: index, cycle: cycle, in: phases),
            elapsed: clamped,
            remainingSeconds: total - clamped,
            isFinished: false
        )
    }

    /// Gentle ease-in-out: starts and ends at rest, so speed is continuous across phases.
    static func ease(_ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return 0.5 - 0.5 * cos(Double.pi * p)
    }

    /// The breath level `progress` of the way from `start` to `end`.
    static func level(from start: Double, to end: Double, progress: Double) -> Double {
        start + (end - start) * ease(progress)
    }

    /// Earlier phases of the same kind as `phases[index]` in this session.
    private static func occurrence(of index: Int, cycle: Int, in phases: [BreathPhase]) -> Int {
        let kind = phases[index].kind
        let perCycle = phases.filter { $0.kind == kind }.count
        let earlierInCycle = phases[..<index].filter { $0.kind == kind }.count
        return cycle * perCycle + earlierInCycle
    }
}

/// Eases the orb from where it was to the new breath when a session restarts
/// mid-breath (for example after picking another pattern), so it never jumps.
nonisolated struct BreathLevelHandoff: Equatable, Sendable {
    let fromLevel: Double
    let startDate: Date
    var duration: TimeInterval = 1.2

    func level(toward target: Double, at date: Date) -> Double {
        guard duration > 0 else { return target }
        let progress = date.timeIntervalSince(startDate) / duration
        if progress >= 1 { return target }
        return BreathEngine.level(from: fromLevel, to: target, progress: progress)
    }

    func isComplete(at date: Date) -> Bool {
        date.timeIntervalSince(startDate) >= duration
    }
}
