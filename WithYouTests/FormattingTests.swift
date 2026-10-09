//
//  FormattingTests.swift
//  WithYouTests
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class FormattingTests: XCTestCase {

    func testHourLabelShowsTheHour() {
        // "9 AM" or "09" depending on the locale's 12/24-hour setting.
        XCTAssertTrue(hourLabel(9).contains("9"), hourLabel(9))
    }

    func testRelativeDayTextToday() {
        XCTAssertEqual(Date().relativeDayText, "today")
    }

    func testRelativeDayTextTomorrow() {
        // Midday tomorrow, so the test can't straddle midnight.
        let tomorrow = TestDates.tomorrow(at: 12, from: Date())
        XCTAssertEqual(tomorrow.relativeDayText, "tomorrow")
    }

    func testRelativeDayTextYesterday() {
        let yesterday = TestDates.day(offset: -1, at: 12, from: Date())
        XCTAssertEqual(yesterday.relativeDayText, "yesterday")
    }
}
