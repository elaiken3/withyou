//
//  TestDates.swift
//  WithYouTests
//
//  Shared date helpers. Every expectation is built from the same `now` the code under
//  test receives, so the tests don't depend on the time of day they run.
//

import Foundation
import XCTest

enum TestDates {
    static var calendar: Calendar { Calendar.current }

    /// The day `reference` falls on (default: today) at a fixed time.
    static func today(at hour: Int, minute: Int = 0, second: Int = 0, reference: Date = Date()) -> Date {
        day(offset: 0, at: hour, minute: minute, second: second, from: reference)
    }

    /// The day after `reference` at a fixed time.
    static func tomorrow(at hour: Int, minute: Int = 0, from reference: Date) -> Date {
        day(offset: 1, at: hour, minute: minute, from: reference)
    }

    /// `offset` days after the day `reference` falls on, at a fixed time.
    static func day(offset: Int, at hour: Int, minute: Int = 0, second: Int = 0, from reference: Date) -> Date {
        let start = calendar.startOfDay(for: reference)
        guard let day = calendar.date(byAdding: .day, value: offset, to: start),
              let result = calendar.date(bySettingHour: hour, minute: minute, second: second, of: day) else {
            preconditionFailure("Could not build a test date")
        }
        return result
    }
}

/// Compares two dates at minute precision (year, month, day, hour, minute).
func assertSameMinute(
    _ actual: Date?,
    _ expected: Date,
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard let actual else {
        XCTFail("Expected \(expected), got nil. \(message)", file: file, line: line)
        return
    }
    let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
    let calendar = TestDates.calendar
    XCTAssertEqual(
        calendar.dateComponents(parts, from: actual),
        calendar.dateComponents(parts, from: expected),
        "Expected \(expected), got \(actual). \(message)",
        file: file,
        line: line
    )
}
