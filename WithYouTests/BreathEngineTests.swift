//
//  BreathEngineTests.swift
//  WithYouTests
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class BreathEngineTests: XCTestCase {

    /// A fixed clock keeps the math exact.
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func state(_ pattern: BreathPattern, at seconds: TimeInterval) -> BreathState {
        BreathEngine.state(pattern: pattern, cycles: pattern.defaultCycles, elapsed: seconds)
    }

    private func date(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    // MARK: - Phase boundaries

    func testStartsEmptyOnTheFirstInhale() {
        let first = state(.calm, at: 0)
        XCTAssertEqual(first.phaseIndex, 0)
        XCTAssertEqual(first.phase.kind, .inhale)
        XCTAssertEqual(first.cycleIndex, 0)
        XCTAssertEqual(first.phaseProgress, 0, accuracy: 1e-9)
        XCTAssertEqual(first.level, 0, accuracy: 1e-9)
        XCTAssertEqual(first.remainingSeconds, 64, accuracy: 1e-9)
        XCTAssertFalse(first.isFinished)
    }

    func testABoundaryBelongsToThePhaseThatStartsThere() {
        let before = state(.calm, at: 3.999)
        XCTAssertEqual(before.phase.kind, .inhale)
        XCTAssertEqual(before.phaseIndex, 0)

        let exhale = state(.calm, at: 4)
        XCTAssertEqual(exhale.phase.kind, .exhale)
        XCTAssertEqual(exhale.phaseIndex, 1)
        XCTAssertEqual(exhale.phaseProgress, 0, accuracy: 1e-9)
        XCTAssertEqual(exhale.level, 1, accuracy: 1e-9)

        let secondBreath = state(.calm, at: 8)
        XCTAssertEqual(secondBreath.phase.kind, .inhale)
        XCTAssertEqual(secondBreath.phaseIndex, 2)
        XCTAssertEqual(secondBreath.cycleIndex, 1)
        XCTAssertEqual(secondBreath.level, 0, accuracy: 1e-9)
    }

    /// Walks every phase of every pattern for a whole session.
    func testEveryPhaseOfEveryPattern() {
        for pattern in BreathPattern.allCases {
            let phases = pattern.phases
            var boundary: TimeInterval = 0

            for cycle in 0..<pattern.defaultCycles {
                for (index, phase) in phases.enumerated() {
                    let expectedIndex = cycle * phases.count + index
                    let label = "\(pattern) breath \(cycle) phase \(index)"

                    let atStart = state(pattern, at: boundary)
                    XCTAssertEqual(atStart.phaseIndex, expectedIndex, label)
                    XCTAssertEqual(atStart.phase, phase, label)
                    XCTAssertEqual(atStart.cycleIndex, cycle, label)
                    XCTAssertEqual(atStart.phaseProgress, 0, accuracy: 1e-9, label)
                    XCTAssertEqual(atStart.phaseStartLevel, pattern.startLevel(ofPhaseAt: index), accuracy: 1e-9, label)

                    let halfway = state(pattern, at: boundary + phase.seconds / 2)
                    XCTAssertEqual(halfway.phaseIndex, expectedIndex, label)
                    XCTAssertEqual(halfway.phaseProgress, 0.5, accuracy: 1e-9, label)

                    let nearlyDone = state(pattern, at: boundary + phase.seconds - 0.001)
                    XCTAssertEqual(nearlyDone.phaseIndex, expectedIndex, label)
                    XCTAssertFalse(nearlyDone.isFinished, label)

                    boundary += phase.seconds
                }
            }
            XCTAssertEqual(boundary, pattern.cycleSeconds * Double(pattern.defaultCycles), accuracy: 1e-9)
            XCTAssertTrue(state(pattern, at: boundary).isFinished, "\(pattern)")
        }
    }

    func testBoxBoundaries() {
        XCTAssertEqual(state(.box, at: 0).phase.kind, .inhale)
        XCTAssertEqual(state(.box, at: 4).phase.kind, .hold)
        XCTAssertEqual(state(.box, at: 8).phase.kind, .exhale)
        XCTAssertEqual(state(.box, at: 12).phase.kind, .hold)
        XCTAssertEqual(state(.box, at: 16).phase.kind, .inhale)
        XCTAssertEqual(state(.box, at: 16).cycleIndex, 1)
        // Holds keep the breath where it was: full after the inhale, empty after the exhale.
        XCTAssertEqual(state(.box, at: 6).level, 1, accuracy: 1e-9)
        XCTAssertEqual(state(.box, at: 14).level, 0, accuracy: 1e-9)
    }

    func testFourSevenEightBoundaries() {
        XCTAssertEqual(state(.fourSevenEight, at: 3.9).phase.kind, .inhale)
        XCTAssertEqual(state(.fourSevenEight, at: 4).phase.kind, .hold)
        XCTAssertEqual(state(.fourSevenEight, at: 10.9).phase.kind, .hold)
        XCTAssertEqual(state(.fourSevenEight, at: 11).phase.kind, .exhale)
        XCTAssertEqual(state(.fourSevenEight, at: 19).phase.kind, .inhale)
        XCTAssertEqual(state(.fourSevenEight, at: 19).cycleIndex, 1)
        XCTAssertEqual(state(.fourSevenEight, at: 7).level, 1, accuracy: 1e-9)
    }

    func testSighBoundaries() {
        let inhale = state(.sigh, at: 1.9)
        XCTAssertEqual(inhale.phase.kind, .inhale)

        let topUp = state(.sigh, at: 2)
        XCTAssertEqual(topUp.phase.kind, .topUp)
        XCTAssertEqual(topUp.level, 0.8, accuracy: 1e-9)

        let exhale = state(.sigh, at: 3)
        XCTAssertEqual(exhale.phase.kind, .exhale)
        XCTAssertEqual(exhale.level, 1, accuracy: 1e-9)

        let nextBreath = state(.sigh, at: 9)
        XCTAssertEqual(nextBreath.phase.kind, .inhale)
        XCTAssertEqual(nextBreath.cycleIndex, 1)
        XCTAssertEqual(nextBreath.level, 0, accuracy: 1e-9)
    }

    func testOccurrenceCountsEachKindAcrossBreaths() {
        // Box has two holds per breath.
        XCTAssertEqual(state(.box, at: 0).occurrence, 0)
        XCTAssertEqual(state(.box, at: 4).occurrence, 0)
        XCTAssertEqual(state(.box, at: 12).occurrence, 1)
        XCTAssertEqual(state(.box, at: 16).occurrence, 1)
        XCTAssertEqual(state(.box, at: 20).occurrence, 2)
        // The fourth exhale of Calm.
        XCTAssertEqual(state(.calm, at: 8 * 3 + 5).occurrence, 3)
    }

    func testRemainingSecondsCountDown() {
        let moment = state(.box, at: 10.25)
        XCTAssertEqual(moment.elapsed, 10.25, accuracy: 1e-9)
        XCTAssertEqual(moment.remainingSeconds, 64 - 10.25, accuracy: 1e-9)
    }

    // MARK: - Finish

    func testFinishesAfterWholeBreaths() {
        for pattern in BreathPattern.allCases {
            let total = pattern.cycleSeconds * Double(pattern.defaultCycles)
            let phaseCount = pattern.phases.count * pattern.defaultCycles

            let almost = state(pattern, at: total - 0.01)
            XCTAssertFalse(almost.isFinished, "\(pattern)")
            XCTAssertEqual(almost.phaseIndex, phaseCount - 1, "\(pattern)")

            for seconds in [total, total + 0.5, total + 1000] {
                let done = state(pattern, at: seconds)
                XCTAssertTrue(done.isFinished, "\(pattern) at \(seconds)")
                // One past the last phase, so finishing is always a change of phase.
                XCTAssertEqual(done.phaseIndex, phaseCount, "\(pattern)")
                XCTAssertEqual(done.remainingSeconds, 0, "\(pattern)")
                XCTAssertEqual(done.elapsed, total, accuracy: 1e-9, "\(pattern)")
                XCTAssertEqual(done.level, 0, accuracy: 1e-9, "\(pattern)")
            }
        }
    }

    func testTimeBeforeTheStartIsTheStart() {
        XCTAssertEqual(state(.calm, at: -5).phaseIndex, 0)
        XCTAssertEqual(state(.calm, at: -5).elapsed, 0)
        XCTAssertEqual(state(.calm, at: .nan).phaseIndex, 0)
    }

    func testCustomBreathCount() {
        let engine = BreathEngine(pattern: .calm, cycles: 2, startDate: start)
        XCTAssertEqual(engine.totalDuration, 16, accuracy: 1e-9)
        XCTAssertFalse(engine.state(at: date(15.9)).isFinished)
        XCTAssertTrue(engine.state(at: date(16)).isFinished)

        // Never fewer than one breath.
        XCTAssertEqual(BreathEngine(pattern: .calm, cycles: 0, startDate: start).cycles, 1)
        // The default is about a minute.
        XCTAssertEqual(BreathEngine(pattern: .box, startDate: start).cycles, BreathPattern.box.defaultCycles)
    }

    // MARK: - Pause accounting

    func testEngineFollowsTheClock() {
        let engine = BreathEngine(pattern: .calm, startDate: start)
        XCTAssertEqual(engine.state(at: date(5)), state(.calm, at: 5))
        XCTAssertEqual(engine.state(at: date(5)).phase.kind, .exhale)
    }

    func testPauseFreezesTheBreath() {
        var engine = BreathEngine(pattern: .calm, startDate: start)
        engine.pause(at: date(10))
        XCTAssertTrue(engine.isPaused)

        let frozen = engine.state(at: date(10))
        XCTAssertEqual(frozen.elapsed, 10, accuracy: 1e-6)
        XCTAssertEqual(engine.state(at: date(500)), frozen)
    }

    func testResumeContinuesExactlyWhereItPaused() {
        var engine = BreathEngine(pattern: .calm, startDate: start)
        let beforePause = engine.state(at: date(10))
        engine.pause(at: date(10))
        engine.resume(at: date(100))
        XCTAssertFalse(engine.isPaused)

        let afterResume = engine.state(at: date(100))
        XCTAssertEqual(afterResume.phaseIndex, beforePause.phaseIndex)
        XCTAssertEqual(afterResume.elapsed, 10, accuracy: 1e-6)
        XCTAssertEqual(afterResume.level, beforePause.level, accuracy: 1e-6)
        XCTAssertEqual(engine.state(at: date(105)).elapsed, 15, accuracy: 1e-6)

        // It still finishes after 64 seconds of breathing, not 64 seconds of clock time.
        XCTAssertFalse(engine.state(at: date(64 + 89)).isFinished)
        XCTAssertTrue(engine.state(at: date(64 + 90)).isFinished)
    }

    func testPausesAddUp() {
        var clock = BreathClock(startDate: start)
        clock.pause(at: date(5))
        clock.resume(at: date(8))
        clock.pause(at: date(20))
        clock.resume(at: date(30))
        XCTAssertEqual(clock.pausedDuration, 13, accuracy: 1e-6)
        XCTAssertEqual(clock.elapsed(at: date(40)), 27, accuracy: 1e-6)
    }

    func testPausingTwiceKeepsTheFirstPause() {
        var clock = BreathClock(startDate: start)
        clock.pause(at: date(5))
        clock.pause(at: date(9))
        XCTAssertEqual(clock.elapsed(at: date(60)), 5, accuracy: 1e-6)

        clock.resume(at: date(10))
        XCTAssertEqual(clock.elapsed(at: date(11)), 6, accuracy: 1e-6)
    }

    func testResumeWithoutAPauseDoesNothing() {
        var clock = BreathClock(startDate: start)
        clock.resume(at: date(50))
        XCTAssertFalse(clock.isPaused)
        XCTAssertEqual(clock.pausedDuration, 0)
        XCTAssertEqual(clock.elapsed(at: date(12)), 12, accuracy: 1e-6)
    }

    func testElapsedIsNeverNegative() {
        let clock = BreathClock(startDate: start)
        XCTAssertEqual(clock.elapsed(at: date(-3)), 0)
    }

    // MARK: - Easing

    func testEaseStartsAndEndsAtRest() {
        XCTAssertEqual(BreathEngine.ease(0), 0, accuracy: 1e-12)
        XCTAssertEqual(BreathEngine.ease(0.5), 0.5, accuracy: 1e-12)
        XCTAssertEqual(BreathEngine.ease(1), 1, accuracy: 1e-12)
        XCTAssertEqual(BreathEngine.ease(-1), 0, accuracy: 1e-12)
        XCTAssertEqual(BreathEngine.ease(2), 1, accuracy: 1e-12)

        var previous = BreathEngine.ease(0)
        for step in 1...100 {
            let value = BreathEngine.ease(Double(step) / 100)
            XCTAssertGreaterThan(value, previous)
            previous = value
        }
    }

    /// No jumps anywhere: the level never moves more than a breath can in 10 ms.
    func testLevelIsContinuousForAWholeSession() {
        for pattern in BreathPattern.allCases {
            let total = pattern.cycleSeconds * Double(pattern.defaultCycles)
            let step = 0.01
            var previous = state(pattern, at: 0).level
            var seconds = step
            while seconds <= total + step {
                let level = state(pattern, at: seconds).level
                XCTAssertGreaterThanOrEqual(level, 0, "\(pattern) at \(seconds)")
                XCTAssertLessThanOrEqual(level, 1, "\(pattern) at \(seconds)")
                XCTAssertLessThan(abs(level - previous), 0.02, "\(pattern) jumps at \(seconds)")
                previous = level
                seconds += step
            }
        }
    }

    /// The level matches on both sides of every boundary, including the join between
    /// breaths, and it's barely moving there (so speed is continuous too).
    func testLevelIsSmoothAcrossEveryBoundary() {
        for pattern in BreathPattern.allCases {
            var boundary: TimeInterval = 0
            for phase in pattern.phases + pattern.phases {
                boundary += phase.seconds
                let label = "\(pattern) at \(boundary)"
                let before = state(pattern, at: boundary - 1e-6).level
                let after = state(pattern, at: boundary + 1e-6).level
                XCTAssertEqual(before, after, accuracy: 1e-4, label)

                let h = 0.001
                let slopeIn = abs(state(pattern, at: boundary).level - state(pattern, at: boundary - h).level) / h
                let slopeOut = abs(state(pattern, at: boundary + h).level - state(pattern, at: boundary).level) / h
                XCTAssertLessThan(slopeIn, 0.05, label)
                XCTAssertLessThan(slopeOut, 0.05, label)
            }
        }
    }

    func testInhaleFillsAndExhaleEmpties() {
        XCTAssertEqual(state(.calm, at: 2).level, 0.5, accuracy: 1e-9)
        XCTAssertEqual(state(.calm, at: 3.999).level, 1, accuracy: 1e-4)
        XCTAssertEqual(state(.calm, at: 6).level, 0.5, accuracy: 1e-9)
        XCTAssertLessThan(state(.calm, at: 7).level, state(.calm, at: 5).level)
    }

    // MARK: - Handoff

    func testHandoffEasesFromWhereTheOrbWas() {
        let handoff = BreathLevelHandoff(fromLevel: 0.8, startDate: start)
        XCTAssertEqual(handoff.level(toward: 0, at: start), 0.8, accuracy: 1e-9)
        XCTAssertEqual(handoff.level(toward: 0.2, at: date(handoff.duration / 2)), 0.5, accuracy: 1e-6)
        XCTAssertEqual(handoff.level(toward: 0.3, at: date(handoff.duration + 0.01)), 0.3, accuracy: 1e-9)
        XCTAssertEqual(handoff.level(toward: 0.3, at: date(handoff.duration + 5)), 0.3, accuracy: 1e-9)

        XCTAssertFalse(handoff.isComplete(at: date(0.1)))
        XCTAssertTrue(handoff.isComplete(at: date(handoff.duration + 0.01)))
    }
}
