//
//  DailyCheckInTests.swift
//  WithYouTests
//
//  Date math for the daily check-in, and the one-time cleanup of the old push server's
//  local state. Every date is built in a fixed time zone, so results don't depend on
//  where or when the tests run.
//

import Foundation
import XCTest
@testable import WithYou

@MainActor
final class DailyCheckInTests: XCTestCase {

    // MARK: - Helpers

    private func makeCalendar(_ identifier: String = "America/New_York") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: identifier) else {
            preconditionFailure("Unknown time zone \(identifier)")
        }
        calendar.timeZone = zone
        return calendar
    }

    private func makeDate(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int, _ minute: Int = 0,
        in calendar: Calendar
    ) -> Date {
        let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        guard let result = calendar.date(from: parts) else {
            preconditionFailure("Could not build a test date")
        }
        return result
    }

    private func wallClock(_ date: Date, in calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    // MARK: - Settings

    func testKeysAndDefaultsMatchTheSettingsScreen() {
        XCTAssertEqual(DailyCheckIn.enabledKey, "dailyCheckInEnabled")
        XCTAssertEqual(DailyCheckIn.minutesKey, "dailyCheckInMinutes")
        XCTAssertEqual(DailyCheckIn.defaultMinutes, 540, "9:00 AM")
        XCTAssertEqual(DailyCheckIn.scheduledCount, 7)
    }

    // MARK: - Minutes ↔ hour and minute

    func testMinutesBecomeHourAndMinute() {
        let cases: [(minutes: Int, hour: Int, minute: Int)] = [
            (540, 9, 0),
            (0, 0, 0),
            (615, 10, 15),
            (1439, 23, 59),
            (1440, 23, 59),   // past the end of the day stays on the same day
            (-30, 0, 0)
        ]
        for item in cases {
            let time = DailyCheckIn.hourAndMinute(fromMinutes: item.minutes)
            XCTAssertEqual(time.hour, item.hour, "\(item.minutes) minutes")
            XCTAssertEqual(time.minute, item.minute, "\(item.minutes) minutes")
        }
    }

    func testPickerDateRoundTrips() {
        let calendar = makeCalendar()
        let day = makeDate(2026, 10, 9, 15, in: calendar)
        for minutes in [0, 540, 615, 1439] {
            let picked = DailyCheckIn.pickerDate(forMinutes: minutes, on: day, calendar: calendar)
            XCTAssertTrue(calendar.isDate(picked, inSameDayAs: day))
            XCTAssertEqual(DailyCheckIn.minutesAfterMidnight(of: picked, calendar: calendar), minutes)
        }
    }

    // MARK: - Fire dates

    func testTodayIsIncludedWhileTheTimeIsAhead() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 9, 8, 30, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 540, restChosenAt: nil, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, makeDate(2026, 10, 9, 9, in: calendar))
        XCTAssertEqual(dates.last, makeDate(2026, 10, 15, 9, in: calendar))
    }

    func testTodayIsSkippedOnceTheTimeHasPassed() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 9, 10, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 540, restChosenAt: nil, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, makeDate(2026, 10, 10, 9, in: calendar))
        XCTAssertEqual(dates.last, makeDate(2026, 10, 16, 9, in: calendar))
    }

    func testTodayIsSkippedAtTheExactTime() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 9, 9, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 540, restChosenAt: nil, calendar: calendar)

        XCTAssertEqual(dates.first, makeDate(2026, 10, 10, 9, in: calendar))
    }

    func testRestingTodaySkipsToday() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 9, 7, in: calendar)
        let restedThisMorning = makeDate(2026, 10, 9, 6, 45, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(
            after: now, minutes: 540, restChosenAt: restedThisMorning, calendar: calendar
        )

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.first, makeDate(2026, 10, 10, 9, in: calendar))
    }

    func testRestingYesterdayDoesNotSkipToday() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 9, 7, in: calendar)
        let restedLastNight = makeDate(2026, 10, 8, 21, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(
            after: now, minutes: 540, restChosenAt: restedLastNight, calendar: calendar
        )

        XCTAssertEqual(dates.first, makeDate(2026, 10, 9, 9, in: calendar))
    }

    func testOneCheckInPerDayOnConsecutiveDays() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 12, 28, 12, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 1290, restChosenAt: nil, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        for (index, fire) in dates.enumerated() {
            let expectedDay = calendar.date(byAdding: .day, value: index, to: calendar.startOfDay(for: now))
            XCTAssertNotNil(expectedDay)
            if let expectedDay {
                XCTAssertTrue(calendar.isDate(fire, inSameDayAs: expectedDay), "Day \(index) crosses the new year cleanly")
            }
            XCTAssertEqual(wallClock(fire, in: calendar).hour, 21)
            XCTAssertEqual(wallClock(fire, in: calendar).minute, 30)
        }
    }

    func testCountOfZeroSchedulesNothing() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 9, 8, in: calendar)
        XCTAssertTrue(DailyCheckIn.upcomingFireDates(after: now, minutes: 540, restChosenAt: nil, count: 0, calendar: calendar).isEmpty)
    }

    // MARK: - Daylight saving

    func testSpringForwardKeepsTheWallClockTime() {
        // In New York, clocks move from 2:00 to 3:00 AM on Sunday, March 8, 2026.
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 7, 8, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 540, restChosenAt: nil, calendar: calendar)

        guard dates.count == 7 else { return XCTFail("Expected 7 dates, got \(dates.count)") }
        for fire in dates {
            XCTAssertEqual(wallClock(fire, in: calendar).hour, 9)
            XCTAssertEqual(wallClock(fire, in: calendar).minute, 0)
        }
        // Saturday 9:00 EST to Sunday 9:00 EDT is only 23 hours.
        XCTAssertEqual(dates[1].timeIntervalSince(dates[0]), 23 * 60 * 60, accuracy: 1)
        XCTAssertEqual(dates[2].timeIntervalSince(dates[1]), 24 * 60 * 60, accuracy: 1)
    }

    func testATimeSkippedBySpringForwardStillComesThatDay() {
        // 2:30 AM doesn't exist on March 8, 2026 in New York.
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 7, 12, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 150, restChosenAt: nil, calendar: calendar)

        guard dates.count == 7 else { return XCTFail("Expected 7 dates, got \(dates.count)") }
        XCTAssertEqual(dates.map { wallClock($0, in: calendar).day }, [8, 9, 10, 11, 12, 13, 14])
        XCTAssertEqual(wallClock(dates[0], in: calendar).hour, 3, "Moves to the next valid time that day")
        XCTAssertEqual(wallClock(dates[1], in: calendar).hour, 2)
        XCTAssertEqual(wallClock(dates[1], in: calendar).minute, 30)
    }

    func testFallBackGivesOneCheckInThatDay() {
        // 1:30 AM happens twice on November 1, 2026 in New York.
        let calendar = makeCalendar()
        let now = makeDate(2026, 10, 31, 12, in: calendar)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 90, restChosenAt: nil, calendar: calendar)

        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(dates.map { wallClock($0, in: calendar).day }, [1, 2, 3, 4, 5, 6, 7])
        for fire in dates {
            XCTAssertEqual(wallClock(fire, in: calendar).hour, 1)
            XCTAssertEqual(wallClock(fire, in: calendar).minute, 30)
        }
    }

    func testOtherTimeZonesUseTheirOwnWallClock() {
        let tokyo = makeCalendar("Asia/Tokyo")
        let now = makeDate(2026, 10, 9, 8, in: tokyo)

        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 540, restChosenAt: nil, calendar: tokyo)

        XCTAssertEqual(dates.first, makeDate(2026, 10, 9, 9, in: tokyo))
    }

    // MARK: - Identifiers and copy

    func testIdentifierIsOnePerDay() {
        let calendar = makeCalendar()
        XCTAssertEqual(
            DailyCheckIn.identifier(for: makeDate(2026, 10, 9, 9, in: calendar), calendar: calendar),
            "checkin-2026-10-09"
        )
        XCTAssertEqual(
            DailyCheckIn.identifier(for: makeDate(2027, 1, 5, 21, 30, in: calendar), calendar: calendar),
            "checkin-2027-01-05"
        )
    }

    func testIdentifiersForAWeekAreUnique() {
        let calendar = makeCalendar()
        let now = makeDate(2026, 3, 7, 1, in: calendar)
        let dates = DailyCheckIn.upcomingFireDates(after: now, minutes: 150, restChosenAt: nil, calendar: calendar)
        let ids = dates.map { DailyCheckIn.identifier(for: $0, calendar: calendar) }

        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertTrue(ids.allSatisfy { $0.hasPrefix(DailyCheckIn.identifierPrefix) })
    }

    func testCopyRotatesAndStaysCalm() {
        let calendar = makeCalendar()
        let start = makeDate(2026, 10, 9, 9, in: calendar)
        var titles: Set<String> = []

        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else {
                XCTFail("Could not build day \(offset)")
                continue
            }
            let copy = DailyCheckIn.message(for: day, calendar: calendar)
            let again = DailyCheckIn.message(for: day, calendar: calendar)
            XCTAssertEqual(copy.title, again.title, "The same day gets the same words")
            titles.insert(copy.title)
        }
        XCTAssertGreaterThan(titles.count, 1, "The words change from day to day")

        for message in DailyCheckIn.messages {
            for text in [message.title, message.body] {
                XCTAssertFalse(text.trimmingCharacters(in: .whitespaces).isEmpty)
                XCTAssertFalse(text.contains("!"), text)
                let lower = text.lowercased()
                for word in ["overdue", "missed", "late", "streak", "should", "hurry", "now!"] {
                    XCTAssertFalse(lower.contains(word), "“\(word)” in: \(text)")
                }
            }
        }
    }
}

// MARK: - Legacy server cleanup

@MainActor
final class LegacyServerCleanupTests: XCTestCase {

    /// Runs `body` with an empty, throwaway UserDefaults suite.
    private func withFreshDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "LegacyServerCleanupTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return XCTFail("Could not create a UserDefaults suite")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }

    private func seedOldState(installId: String, in defaults: UserDefaults) {
        defaults.set("abc123", forKey: "withyou.apns_token")
        defaults.set("sig", forKey: "withyou.apns_last_sent_signature")
        defaults.set("sig", forKey: "withyou.apns_last_failure_signature")
        defaults.set(Date(), forKey: "withyou.apns_last_failure_at")
        defaults.set(true, forKey: "withyou.server_sharing_enabled")
        defaults.set(installId, forKey: "withyou.install_id")
        defaults.set(true, forKey: "unrelatedSetting")
    }

    func testRemovesOldStateAndTheInstallSecretOnce() {
        withFreshDefaults { defaults in
            seedOldState(installId: "install-1", in: defaults)
            var deletedAccounts: [String] = []

            LegacyServerCleanup.runIfNeeded(defaults: defaults) { account in
                deletedAccounts.append(account)
                return true
            }

            XCTAssertEqual(deletedAccounts, ["install_secret.install-1"])
            for key in LegacyServerCleanup.legacyKeys {
                XCTAssertNil(defaults.object(forKey: key), key)
            }
            XCTAssertTrue(defaults.bool(forKey: "unrelatedSetting"), "Other settings are left alone")
            XCTAssertTrue(defaults.bool(forKey: LegacyServerCleanup.doneKey))

            // A second launch does nothing.
            LegacyServerCleanup.runIfNeeded(defaults: defaults) { account in
                deletedAccounts.append(account)
                return true
            }
            XCTAssertEqual(deletedAccounts.count, 1)
        }
    }

    func testFreshInstallSkipsTheKeychain() {
        withFreshDefaults { defaults in
            var calls = 0

            LegacyServerCleanup.runIfNeeded(defaults: defaults) { _ in
                calls += 1
                return true
            }

            XCTAssertEqual(calls, 0)
            XCTAssertTrue(defaults.bool(forKey: LegacyServerCleanup.doneKey))
        }
    }

    func testTriesAgainLaterWhenTheKeychainIsUnavailable() {
        withFreshDefaults { defaults in
            seedOldState(installId: "install-2", in: defaults)

            LegacyServerCleanup.runIfNeeded(defaults: defaults) { _ in false }

            XCTAssertFalse(defaults.bool(forKey: LegacyServerCleanup.doneKey))
            XCTAssertEqual(defaults.string(forKey: "withyou.install_id"), "install-2", "Kept so the secret can still be found")

            LegacyServerCleanup.runIfNeeded(defaults: defaults) { _ in true }

            XCTAssertTrue(defaults.bool(forKey: LegacyServerCleanup.doneKey))
            XCTAssertNil(defaults.object(forKey: "withyou.install_id"))
        }
    }
}
