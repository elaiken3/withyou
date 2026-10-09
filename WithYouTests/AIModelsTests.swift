//
//  AIModelsTests.swift
//  WithYouTests
//

import Foundation
import SwiftData
import XCTest
@testable import WithYou

@MainActor
final class AIModelsTests: XCTestCase {

    // MARK: - Energy

    func testEnergyRawValuesMatchTheAPI() {
        XCTAssertEqual(EnergyLevel.allCases, [.low, .okay, .good])
        XCTAssertEqual(EnergyLevel.allCases.map(\.rawValue), ["low", "okay", "good"])
        XCTAssertEqual(EnergyLevel.allCases.map(\.title), ["Low", "Okay", "Good"])
        XCTAssertEqual(EnergyLevel.okay.id, "okay")
    }

    // MARK: - Stuck blockers

    func testBlockerRawValuesMatchTheAPI() {
        XCTAssertEqual(
            StuckBlocker.allCases.map(\.rawValue),
            ["dont_know_where_to_start", "too_big", "boring", "worried", "low_energy", "distracted"]
        )
        XCTAssertEqual(StuckBlocker.tooBig.id, "too_big")
    }

    func testBlockerLabelsAreCalm() {
        XCTAssertEqual(StuckBlocker.dontKnowWhereToStart.label, "I don’t know where to start")
        XCTAssertEqual(StuckBlocker.distracted.label, "I keep getting distracted")
        for blocker in StuckBlocker.allCases {
            XCTAssertFalse(blocker.label.isEmpty, blocker.rawValue)
            XCTAssertFalse(blocker.label.contains("!"), blocker.rawValue)
            XCTAssertFalse(blocker.label.contains("'"), "Use curly apostrophes: \(blocker.label)")
        }
    }

    // MARK: - Capture context

    func testCaptureContextWithoutProfileUsesDefaultHours() {
        let before = Date()
        let context = CaptureContext.current(profile: nil)

        XCTAssertEqual(context.morningHour, 9)
        XCTAssertEqual(context.eveningHour, 19)
        XCTAssertEqual(context.timeZone, TimeZone.current)
        XCTAssertGreaterThanOrEqual(context.now, before)
        XCTAssertLessThan(context.now.timeIntervalSince(before), 5)
    }

    func testCaptureContextUsesTheProfilesHours() {
        _ = AppModelContainer.shared
        let profile = UserProfile(name: "Test", morningHour: 7, eveningHour: 21)
        let context = CaptureContext.current(profile: profile)

        XCTAssertEqual(context.morningHour, 7)
        XCTAssertEqual(context.eveningHour, 21)
    }

    // MARK: - Suggestions

    func testCaptureSuggestionsGetTheirOwnIds() {
        let first = CaptureSuggestion(title: "Call mom", firstStep: "Find the number.", estimateMinutes: 5, originalText: "call mom")
        let second = CaptureSuggestion(title: "Call mom", firstStep: "Find the number.", estimateMinutes: 5, originalText: "call mom")

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(first.scheduledAt, "No date means the Inbox")
        XCTAssertNotEqual(first, second)
    }

    func testCaptureDraftDecodesTheContractShape() throws {
        let json = """
        [
          {"title": "Email landlord", "first_step": "Open Mail.", "estimate_minutes": 4,
           "when": {"day_offset": 1, "hour": 9, "minute": 30}},
          {"title": "Buy milk", "first_step": "Add it to the list.", "estimate_minutes": 3, "when": null},
          {"title": "Water plants", "first_step": "Fill the can.", "estimate_minutes": 2}
        ]
        """
        let drafts = try JSONDecoder().decode([AICaptureDraft].self, from: Data(json.utf8))

        XCTAssertEqual(drafts.count, 3)
        XCTAssertEqual(drafts[0].firstStep, "Open Mail.")
        XCTAssertEqual(drafts[0].estimateMinutes, 4)
        XCTAssertEqual(drafts[0].when, CaptureWhen(dayOffset: 1, hour: 9, minute: 30))
        XCTAssertNil(drafts[1].when)
        XCTAssertNil(drafts[2].when)
    }
}
