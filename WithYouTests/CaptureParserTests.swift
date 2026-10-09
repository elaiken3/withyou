//
//  CaptureParserTests.swift
//  WithYouTests
//

import Foundation
import XCTest
@testable import WithYou

/// With no profile, part-of-day words use the default hours:
/// morning 9, afternoon 13, evening 19.
@MainActor
final class CaptureParserTests: XCTestCase {

    private func parse(_ raw: String, now: Date) -> ParsedCapture {
        CaptureParser().parse(raw, profile: nil, now: now)
    }

    // MARK: - Day + part of day

    func testTomorrowMorningUsesMorningHourTomorrow() {
        let now = TestDates.today(at: 10)
        let parsed = parse("Email landlord tomorrow morning", now: now)

        XCTAssertEqual(parsed.title, "Email landlord")
        assertSameMinute(parsed.scheduledAt, TestDates.tomorrow(at: 9, from: now))
        XCTAssertFalse(parsed.startStep.isEmpty, "Every capture gets a gentle first step")
        XCTAssertGreaterThan(parsed.estimateMinutes, 0)
    }

    func testTonightUsesEveningHourTodayAndDropsLeadingPhrase() {
        let now = TestDates.today(at: 10)
        let parsed = parse("remind me to pay rent tonight", now: now)

        XCTAssertEqual(parsed.title, "Pay rent")
        assertSameMinute(parsed.scheduledAt, TestDates.today(at: 19, reference: now))
    }

    // MARK: - Clock times

    func testClockTimeLaterTodayStaysToday() {
        let now = TestDates.today(at: 10)
        let parsed = parse("Call mom at 3pm", now: now)

        XCTAssertEqual(parsed.title, "Call mom")
        assertSameMinute(parsed.scheduledAt, TestDates.today(at: 15, reference: now))
    }

    func testClockTimeThatAlreadyPassedRollsToTomorrow() {
        let now = TestDates.today(at: 17)
        let parsed = parse("Call mom at 3pm", now: now)

        XCTAssertEqual(parsed.title, "Call mom")
        assertSameMinute(parsed.scheduledAt, TestDates.tomorrow(at: 15, from: now))
    }

    func testTomorrowWithClockTime() {
        let now = TestDates.today(at: 10)
        let parsed = parse("Call dentist tomorrow at 4pm", now: now)

        XCTAssertEqual(parsed.title, "Call dentist")
        assertSameMinute(parsed.scheduledAt, TestDates.tomorrow(at: 16, from: now))
    }

    // MARK: - No time → Inbox

    func testNoTimeGoesToInbox() {
        let now = TestDates.today(at: 10)
        let parsed = parse("Buy milk", now: now)

        XCTAssertEqual(parsed.title, "Buy milk")
        XCTAssertNil(parsed.scheduledAt)
    }

    func testTitleIsCapitalized() {
        let parsed = parse("buy milk", now: TestDates.today(at: 10))

        XCTAssertEqual(parsed.title, "Buy milk")
        XCTAssertNil(parsed.scheduledAt)
    }

    func testPastDayIsNotScheduled() {
        let parsed = parse("call mom yesterday", now: TestDates.today(at: 10))

        XCTAssertNil(parsed.scheduledAt, "A day that already went by goes to the Inbox, never into the past")
    }
}
