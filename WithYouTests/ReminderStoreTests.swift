//
//  ReminderStoreTests.swift
//  WithYouTests
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class ReminderStoreTests: XCTestCase {

    // MARK: - Notification copy

    func testGentleBodyIncludesStepAndEstimate() {
        let body = ReminderStore.notificationBody(startStep: "Open Mail", estimateMinutes: 5, tone: .gentle)

        XCTAssertTrue(body.contains("Open Mail"), body)
        XCTAssertTrue(body.contains("5 min"), body)
    }

    func testFirmBodyIncludesStepAndEstimate() {
        let firm = ReminderStore.notificationBody(startStep: "Open Mail", estimateMinutes: 5, tone: .firm)
        let gentle = ReminderStore.notificationBody(startStep: "Open Mail", estimateMinutes: 5, tone: .gentle)

        XCTAssertTrue(firm.contains("Open Mail"), firm)
        XCTAssertTrue(firm.contains("5 min"), firm)
        XCTAssertNotEqual(firm, gentle, "Firm tone should read differently from gentle")
    }

    func testEmptyStepDoesNotLeaveABlankStep() {
        for tone in [ReminderTone.gentle, .firm] {
            let empty = ReminderStore.notificationBody(startStep: "", estimateMinutes: 5, tone: tone)
            let blank = ReminderStore.notificationBody(startStep: "   \n", estimateMinutes: 5, tone: tone)

            XCTAssertFalse(empty.isEmpty)
            XCTAssertEqual(empty, blank, "Whitespace-only steps count as empty")
            XCTAssertFalse(empty.contains("()"), empty)
            XCTAssertFalse(empty.contains(": ."), empty)
            XCTAssertFalse(empty.contains(":  "), empty)
        }
    }

    func testCopyIsNeverShaming() {
        let bodies = [ReminderTone.gentle, .firm].flatMap { tone in
            ["", "Open Mail"].map { ReminderStore.notificationBody(startStep: $0, estimateMinutes: 5, tone: tone) }
        }
        for body in bodies {
            let lower = body.lowercased()
            for word in ["overdue", "missed", "failed"] {
                XCTAssertFalse(lower.contains(word), "“\(word)” in: \(body)")
            }
        }
    }

    // MARK: - Time helpers

    func testNextMorningIsTomorrowAtNine() {
        let now = TestDates.today(at: 10)
        assertSameMinute(ReminderStore.nextMorning(profile: nil, after: now), TestDates.tomorrow(at: 9, from: now))
    }

    func testNextMorningIsTomorrowEvenBeforeNine() {
        let now = TestDates.today(at: 7)
        assertSameMinute(ReminderStore.nextMorning(profile: nil, after: now), TestDates.tomorrow(at: 9, from: now))
    }

    func testThisEveningIsTodayAtSevenPM() {
        let now = TestDates.today(at: 10)
        assertSameMinute(ReminderStore.thisEvening(profile: nil, now: now), TestDates.today(at: 19, reference: now))
    }

    func testThisEveningIsNilOnceTheEveningHasPassed() {
        let now = TestDates.today(at: 20)
        XCTAssertNil(ReminderStore.thisEvening(profile: nil, now: now))
    }

    func testRoundedUpMovesToNextFiveMinuteMark() {
        let date = TestDates.today(at: 10, minute: 2)
        XCTAssertEqual(ReminderStore.roundedUp(date), TestDates.today(at: 10, minute: 5, reference: date))
    }

    func testRoundedUpKeepsAFiveMinuteMark() {
        let date = TestDates.today(at: 10, minute: 5)
        XCTAssertEqual(ReminderStore.roundedUp(date), date)
    }

    func testRoundedUpZeroesSeconds() {
        let date = TestDates.today(at: 10, minute: 2, second: 30)
        let rounded = ReminderStore.roundedUp(date)

        XCTAssertEqual(TestDates.calendar.component(.second, from: rounded), 0)
        XCTAssertEqual(TestDates.calendar.component(.minute, from: rounded) % 5, 0)
        XCTAssertEqual(rounded, TestDates.today(at: 10, minute: 5, reference: date))
    }
}
