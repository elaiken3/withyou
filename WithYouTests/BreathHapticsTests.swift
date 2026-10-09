//
//  BreathHapticsTests.swift
//  WithYouTests
//
//  The haptic curves are pure; the Core Haptics player itself needs a device.
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class BreathHapticsTests: XCTestCase {

    private func curve(_ pattern: BreathPattern, at seconds: TimeInterval, samples: Int = 8) -> BreathHapticCurve {
        let state = BreathEngine.state(pattern: pattern, cycles: pattern.defaultCycles, elapsed: seconds)
        return BreathHapticCurve(state: state, samples: samples)
    }

    private func assertRising(_ curve: BreathHapticCurve, file: StaticString = #filePath, line: UInt = #line) {
        for (earlier, later) in zip(curve.points, curve.points.dropFirst()) {
            XCTAssertLessThan(earlier.time, later.time, file: file, line: line)
            XCTAssertLessThan(earlier.intensity, later.intensity, file: file, line: line)
        }
    }

    private func assertFalling(_ curve: BreathHapticCurve, file: StaticString = #filePath, line: UInt = #line) {
        for (earlier, later) in zip(curve.points, curve.points.dropFirst()) {
            XCTAssertLessThan(earlier.time, later.time, file: file, line: line)
            XCTAssertGreaterThan(earlier.intensity, later.intensity, file: file, line: line)
        }
    }

    func testInhaleSwells() {
        let inhale = curve(.calm, at: 0)
        XCTAssertEqual(inhale.kind, .inhale)
        XCTAssertEqual(inhale.duration, 4, accuracy: 1e-9)
        XCTAssertEqual(inhale.points.count, 8)
        XCTAssertEqual(inhale.points.first?.time ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(inhale.points.last?.time ?? -1, 4, accuracy: 1e-9)
        XCTAssertEqual(inhale.points.first?.intensity ?? -1, BreathHapticCurve.intensity(for: .inhale, level: 0), accuracy: 1e-9)
        XCTAssertEqual(inhale.points.last?.intensity ?? -1, 1, accuracy: 1e-9)
        assertRising(inhale)
    }

    func testExhaleFades() {
        let exhale = curve(.calm, at: 4)
        XCTAssertEqual(exhale.kind, .exhale)
        XCTAssertEqual(exhale.duration, 4, accuracy: 1e-9)
        XCTAssertEqual(exhale.points.first?.intensity ?? -1, 1, accuracy: 1e-9)
        XCTAssertEqual(exhale.points.last?.intensity ?? -1, BreathHapticCurve.intensity(for: .exhale, level: 0), accuracy: 1e-9)
        assertFalling(exhale)
    }

    func testHoldIsNearlyStill() {
        for seconds in [4.0, 12.0] {
            let hold = curve(.box, at: seconds)
            XCTAssertEqual(hold.kind, .hold)
            let first = hold.points.first?.intensity ?? -1
            for point in hold.points {
                XCTAssertEqual(point.intensity, first, accuracy: 1e-9)
                XCTAssertLessThanOrEqual(point.intensity, 0.15)
            }
        }
    }

    func testTopUpSwellsToFull() {
        let topUp = curve(.sigh, at: 2)
        XCTAssertEqual(topUp.kind, .topUp)
        XCTAssertEqual(topUp.duration, 1, accuracy: 1e-9)
        XCTAssertEqual(topUp.points.first?.intensity ?? -1, BreathHapticCurve.intensity(for: .topUp, level: 0.8), accuracy: 1e-9)
        XCTAssertEqual(topUp.points.last?.intensity ?? -1, 1, accuracy: 1e-9)
        assertRising(topUp)
    }

    /// After a pause, only the rest of the phase plays, starting where the breath is.
    func testResumingMidPhasePlaysOnlyTheRest() {
        let state = BreathEngine.state(pattern: .fourSevenEight, cycles: 3, elapsed: 13)
        let rest = BreathHapticCurve(state: state)
        XCTAssertEqual(rest.kind, .exhale)
        XCTAssertEqual(rest.duration, 6, accuracy: 1e-9)
        XCTAssertEqual(rest.points.first?.intensity ?? -1, BreathHapticCurve.intensity(for: .exhale, level: state.level), accuracy: 1e-9)
        XCTAssertEqual(rest.points.last?.time ?? -1, 6, accuracy: 1e-9)
        assertFalling(rest)
    }

    func testFinishedHasNothingToPlay() {
        XCTAssertEqual(curve(.calm, at: 64).duration, 0)
    }

    func testStaysWithinCoreHapticsLimits() {
        XCTAssertEqual(curve(.calm, at: 0, samples: 100).points.count, BreathHapticCurve.maxPoints)
        XCTAssertEqual(curve(.calm, at: 0, samples: 0).points.count, 2)

        for pattern in BreathPattern.allCases {
            var seconds: TimeInterval = 0
            while seconds < pattern.cycleSeconds * 2 {
                for point in curve(pattern, at: seconds).points {
                    XCTAssertGreaterThanOrEqual(point.intensity, 0, "\(pattern) at \(seconds)")
                    XCTAssertLessThanOrEqual(point.intensity, 1, "\(pattern) at \(seconds)")
                    XCTAssertGreaterThanOrEqual(point.time, 0, "\(pattern) at \(seconds)")
                }
                seconds += 0.25
            }
        }
    }

    func testIntensityIsClamped() {
        XCTAssertEqual(BreathHapticCurve.intensity(for: .inhale, level: 2), 1, accuracy: 1e-9)
        XCTAssertEqual(BreathHapticCurve.intensity(for: .exhale, level: -1), 0.05, accuracy: 1e-9)
    }
}
