//
//  BreathPhaseTrackerTests.swift
//  WithYouTests
//
//  What Refocus does at each phase change. The view adds only the clock, the
//  haptics toggle and the pause check on top of this.
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class BreathPhaseTrackerTests: XCTestCase {

    private func state(_ pattern: BreathPattern, at seconds: TimeInterval) -> BreathState {
        BreathEngine.state(pattern: pattern, cycles: pattern.defaultCycles, elapsed: seconds)
    }

    /// The moment each phase of a whole session starts, then the finish.
    private func boundaries(_ pattern: BreathPattern) -> [BreathState] {
        var moments: [BreathState] = []
        var seconds: TimeInterval = 0
        for _ in 0..<pattern.defaultCycles {
            for phase in pattern.phases {
                moments.append(state(pattern, at: seconds))
                seconds += phase.seconds
            }
        }
        moments.append(state(pattern, at: seconds))
        return moments
    }

    private func spokenWord(_ event: BreathPhaseEvent?) -> String? {
        guard case .some(.phase(let word, _)) = event else { return nil }
        return word
    }

    func testEachPhaseRunsOnceAndTheFinishRunsOnce() {
        for pattern in BreathPattern.allCases {
            var tracker = BreathPhaseTracker()
            var phaseEvents = 0
            var finishes = 0

            for moment in boundaries(pattern) {
                // Every frame of a phase reports the same index; only the first one counts.
                for _ in 0..<3 {
                    switch tracker.advance(to: moment, runCount: 0) {
                    case .some(.phase): phaseEvents += 1
                    case .some(.finished): finishes += 1
                    case .none: break
                    }
                }
                XCTAssertEqual(tracker.handledIndex, moment.phaseIndex, "\(pattern)")
            }

            XCTAssertEqual(phaseEvents, pattern.phases.count * pattern.defaultCycles, "\(pattern)")
            XCTAssertEqual(finishes, 1, "\(pattern)")
        }
    }

    func testAnEarlierOrRepeatedPhaseIsIgnored() {
        var tracker = BreathPhaseTracker()
        // Calm: the second exhale (index 3) starts at 12 seconds.
        XCTAssertNotNil(tracker.advance(to: state(.calm, at: 12), runCount: 0))
        XCTAssertEqual(tracker.handledIndex, 3)

        // A later frame of the same phase, then stale frames from earlier phases.
        XCTAssertNil(tracker.advance(to: state(.calm, at: 13), runCount: 0))
        XCTAssertNil(tracker.advance(to: state(.calm, at: 5), runCount: 0))
        XCTAssertNil(tracker.advance(to: state(.calm, at: 0), runCount: 0))
        XCTAssertEqual(tracker.handledIndex, 3)

        XCTAssertNotNil(tracker.advance(to: state(.calm, at: 16), runCount: 0))
        XCTAssertEqual(tracker.handledIndex, 4)
    }

    func testMissedFramesJumpToTheNewestPhase() {
        var tracker = BreathPhaseTracker()
        _ = tracker.advance(to: state(.box, at: 0), runCount: 0)

        // Box: the second hold (index 3) starts at 12 seconds.
        let secondHold = state(.box, at: 13)
        let event = tracker.advance(to: secondHold, runCount: 0)
        XCTAssertEqual(tracker.handledIndex, 3)
        XCTAssertEqual(
            event,
            .phase(word: BreathWords.word(for: .hold, occurrence: 1), curve: BreathHapticCurve(state: secondHold))
        )
    }

    func testEventsCarryTheWordsAndHapticForThatPhase() {
        var tracker = BreathPhaseTracker()
        let exhale = state(.calm, at: 4.5)
        let event = tracker.advance(to: exhale, runCount: 0)
        XCTAssertEqual(event, .phase(word: "Breathe out", curve: BreathHapticCurve(state: exhale)))
    }

    func testFinishRunsOnceAndNothingRunsAfterIt() {
        for pattern in BreathPattern.allCases {
            let total = pattern.cycleSeconds * Double(pattern.defaultCycles)
            var tracker = BreathPhaseTracker()
            XCTAssertNotNil(tracker.advance(to: state(pattern, at: total - 0.5), runCount: 0), "\(pattern)")

            let finish = tracker.advance(to: state(pattern, at: total), runCount: 0)
            XCTAssertEqual(finish, .finished, "\(pattern)")
            XCTAssertEqual(tracker.handledIndex, pattern.phases.count * pattern.defaultCycles, "\(pattern)")

            XCTAssertNil(tracker.advance(to: state(pattern, at: total + 5), runCount: 0), "\(pattern)")
            XCTAssertNil(tracker.advance(to: state(pattern, at: total - 0.5), runCount: 0), "\(pattern)")
        }
    }

    func testResetLetsTheFirstPhaseRunAgain() {
        var tracker = BreathPhaseTracker()
        let first = state(.calm, at: 0)
        XCTAssertNotNil(tracker.advance(to: first, runCount: 0))
        XCTAssertNil(tracker.advance(to: first, runCount: 0))

        // "Again" after a finished session.
        let total = BreathPattern.calm.cycleSeconds * Double(BreathPattern.calm.defaultCycles)
        let finish = tracker.advance(to: state(.calm, at: total), runCount: 0)
        XCTAssertEqual(finish, .finished)

        tracker.reset()
        XCTAssertEqual(tracker.handledIndex, -1)
        XCTAssertNotNil(tracker.advance(to: first, runCount: 1))
        XCTAssertEqual(tracker.handledIndex, 0)
    }

    func testAgainStartsWithDifferentWords() {
        for pattern in BreathPattern.allCases {
            var tracker = BreathPhaseTracker()
            let firstRun = spokenWord(tracker.advance(to: state(pattern, at: 0), runCount: 0))

            tracker.reset()
            let secondRun = spokenWord(tracker.advance(to: state(pattern, at: 0), runCount: 1))

            XCTAssertEqual(firstRun, "Breathe in", "\(pattern)")
            XCTAssertEqual(secondRun, "In, slowly", "\(pattern)")
        }
    }

    func testWordsNeverRepeatForTheSameKindOfPhase() {
        for runCount in 0..<2 {
            for pattern in BreathPattern.allCases {
                var tracker = BreathPhaseTracker()
                var lastWords: [BreathPhaseKind: String] = [:]

                for moment in boundaries(pattern) where !moment.isFinished {
                    let label = "\(pattern) run \(runCount) phase \(moment.phaseIndex)"
                    guard let word = spokenWord(tracker.advance(to: moment, runCount: runCount)) else {
                        XCTFail("No words for \(label)")
                        continue
                    }
                    XCTAssertEqual(word, BreathWords.word(for: moment.phase.kind, occurrence: moment.occurrence + runCount), label)
                    XCTAssertNotEqual(lastWords[moment.phase.kind], word, label)
                    lastWords[moment.phase.kind] = word
                }
            }
        }
    }
}
