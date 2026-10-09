//
//  BreathPatternTests.swift
//  WithYouTests
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class BreathPatternTests: XCTestCase {

    // MARK: - Shapes

    func testCycleLengths() {
        XCTAssertEqual(BreathPattern.calm.cycleSeconds, 8)
        XCTAssertEqual(BreathPattern.box.cycleSeconds, 16)
        XCTAssertEqual(BreathPattern.fourSevenEight.cycleSeconds, 19)
        XCTAssertEqual(BreathPattern.sigh.cycleSeconds, 9)
    }

    func testCalmMatchesTheOriginalRhythm() {
        XCTAssertEqual(BreathPattern.calm.phases.map(\.kind), [.inhale, .exhale])
        XCTAssertEqual(BreathPattern.calm.phases.map(\.seconds), [4, 4])
    }

    func testPhasesOfEachPattern() {
        XCTAssertEqual(BreathPattern.box.phases.map(\.kind), [.inhale, .hold, .exhale, .hold])
        XCTAssertEqual(BreathPattern.box.phases.map(\.seconds), [4, 4, 4, 4])

        XCTAssertEqual(BreathPattern.fourSevenEight.phases.map(\.kind), [.inhale, .hold, .exhale])
        XCTAssertEqual(BreathPattern.fourSevenEight.phases.map(\.seconds), [4, 7, 8])

        XCTAssertEqual(BreathPattern.sigh.phases.map(\.kind), [.inhale, .topUp, .exhale])
        XCTAssertEqual(BreathPattern.sigh.phases.map(\.seconds), [2, 1, 6])
    }

    func testSessionsAreWholeBreathsOfAboutAMinute() {
        XCTAssertEqual(BreathPattern.calm.defaultCycles, 8)
        XCTAssertEqual(BreathPattern.box.defaultCycles, 4)
        XCTAssertEqual(BreathPattern.fourSevenEight.defaultCycles, 3)
        XCTAssertEqual(BreathPattern.sigh.defaultCycles, 7)

        for pattern in BreathPattern.allCases {
            let total = pattern.cycleSeconds * Double(pattern.defaultCycles)
            XCTAssertGreaterThanOrEqual(total, 50, "\(pattern)")
            XCTAssertLessThanOrEqual(total, 70, "\(pattern)")
        }
    }

    /// Breaths join up smoothly: each starts empty with an inhale and ends empty.
    func testEveryPatternStartsWithAnInhaleAndEndsEmpty() {
        for pattern in BreathPattern.allCases {
            XCTAssertEqual(pattern.phases.first?.kind, .inhale, "\(pattern)")
            XCTAssertEqual(pattern.phases.last?.endLevel, 0, "\(pattern)")
            XCTAssertEqual(pattern.startLevel(ofPhaseAt: 0), 0, "\(pattern)")

            for phase in pattern.phases {
                XCTAssertGreaterThan(phase.seconds, 0, "\(pattern)")
                XCTAssertGreaterThanOrEqual(phase.endLevel, 0, "\(pattern)")
                XCTAssertLessThanOrEqual(phase.endLevel, 1, "\(pattern)")
            }
        }
    }

    func testEachPhaseMovesTheBreathTheRightWay() {
        for pattern in BreathPattern.allCases {
            for (index, phase) in pattern.phases.enumerated() {
                let start = pattern.startLevel(ofPhaseAt: index)
                let label = "\(pattern) phase \(index)"
                switch phase.kind {
                case .inhale, .topUp:
                    XCTAssertGreaterThan(phase.endLevel, start, label)
                case .exhale:
                    XCTAssertLessThan(phase.endLevel, start, label)
                case .hold:
                    XCTAssertEqual(phase.endLevel, start, label)
                }
            }
        }
    }

    // MARK: - Storage

    /// Stored in AppStorage (`refocusPattern`), so these must never change.
    func testRawValuesAreStable() {
        XCTAssertEqual(BreathPattern.calm.rawValue, "calm")
        XCTAssertEqual(BreathPattern.box.rawValue, "box")
        XCTAssertEqual(BreathPattern.fourSevenEight.rawValue, "fourSevenEight")
        XCTAssertEqual(BreathPattern.sigh.rawValue, "sigh")
        XCTAssertNil(BreathPattern(rawValue: "unknown"))
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(BreathPattern.allCases)
        let decoded = try JSONDecoder().decode([BreathPattern].self, from: data)
        XCTAssertEqual(decoded, BreathPattern.allCases)
    }

    // MARK: - Copy

    func testTitlesAreShortAndCalm() {
        for pattern in BreathPattern.allCases {
            XCTAssertFalse(pattern.title.isEmpty)
            XCTAssertFalse(pattern.detail.isEmpty)
            XCTAssertTrue(pattern.menuTitle.hasPrefix(pattern.title))
            XCTAssertFalse(pattern.menuTitle.contains("!"))
        }
    }

    func testFirstWordsMatchTheOriginal() {
        XCTAssertEqual(BreathWords.word(for: .inhale, occurrence: 0), "Breathe in")
        XCTAssertEqual(BreathWords.word(for: .exhale, occurrence: 0), "Breathe out")
    }

    func testWordsRotateWithoutRepeating() {
        for kind in BreathPhaseKind.allCases {
            for occurrence in 0..<12 {
                XCTAssertNotEqual(
                    BreathWords.word(for: kind, occurrence: occurrence),
                    BreathWords.word(for: kind, occurrence: occurrence + 1),
                    "\(kind) \(occurrence)"
                )
            }
        }
    }

    func testWordsAreGentle() {
        for kind in BreathPhaseKind.allCases {
            let words = BreathWords.phrases(for: kind)
            XCTAssertGreaterThan(words.count, 1, "\(kind)")
            for word in words {
                XCTAssertFalse(word.isEmpty)
                XCTAssertFalse(word.contains("!"), word)
            }
        }
    }

    func testNegativeOccurrenceIsSafe() {
        XCTAssertFalse(BreathWords.word(for: .hold, occurrence: -3).isEmpty)
    }
}
