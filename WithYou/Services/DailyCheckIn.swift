//
//  DailyCheckIn.swift
//  WithYou
//

import Foundation
import UserNotifications
import OSLog

/// An optional daily check-in: one quiet local notification at a time the person picks.
///
/// - Off by default. Turning it on in Settings is the only moment it asks for notification
///   permission; refreshing never prompts.
/// - The next 7 check-ins are scheduled as separate one-time notifications
///   (`checkin-YYYY-MM-DD`) and refreshed at launch, when the app comes back and when the
///   settings change. Nothing repeats forever, so a week away doesn't pile anything up.
/// - Today is skipped once today's time has passed, or after the person lets today rest.
/// - Tapping one opens Today (see `NotificationManager`).
enum DailyCheckIn {
    /// UserDefaults keys; also used by `@AppStorage` in `DailyCheckInSection`.
    nonisolated static let enabledKey = "dailyCheckInEnabled"
    nonisolated static let minutesKey = "dailyCheckInMinutes"
    /// When the person last chose "Let today rest" (seconds since the reference date).
    nonisolated static let restChosenAtKey = "dailyCheckInRestChosenAt"

    /// 9:00 AM, in minutes after midnight.
    nonisolated static let defaultMinutes = 9 * 60
    /// How many check-ins are scheduled ahead.
    nonisolated static let scheduledCount = 7
    nonisolated static let identifierPrefix = "checkin-"

    private static let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "checkin")
    private static var refreshTask: Task<Void, Never>?

    // MARK: - Settings

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// The chosen time in minutes after midnight (default 9:00 AM).
    static var chosenMinutes: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: minutesKey) != nil else { return defaultMinutes }
        return clampedMinutes(defaults.integer(forKey: minutesKey))
    }

    /// When the person last let a day rest, if ever.
    static var restChosenAt: Date? {
        guard let seconds = UserDefaults.standard.object(forKey: restChosenAtKey) as? Double else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds)
    }

    /// Call when the person chooses "Let today rest": today's check-in is skipped.
    static func letTodayRest(at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSinceReferenceDate, forKey: restChosenAtKey)
        reschedule()
    }

    /// Call from the Undo of "Let today rest": today's check-in comes back if its time is ahead.
    static func undoLetTodayRest() {
        UserDefaults.standard.removeObject(forKey: restChosenAtKey)
        reschedule()
    }

    /// Called when the person turns the check-in on. Asks for notification permission if it
    /// was never asked, then schedules. Returns false when notifications are off for WithYou.
    static func turnedOn() async -> Bool {
        let allowed = await NotificationManager.shared.ensureAuthorization()
        reschedule()
        return allowed
    }

    // MARK: - Scheduling

    /// Brings the pending check-ins in line with the settings. Safe to call often:
    /// calls run one after another, and each replaces what the last one scheduled.
    static func reschedule() {
        let previous = refreshTask
        refreshTask = Task {
            if let previous {
                await previous.value
            }
            await refresh(now: Date())
        }
    }

    private static func refresh(now: Date) async {
        let center = UNUserNotificationCenter.current()

        let pending = await center.pendingNotificationRequests()
        let stale = pending.map { $0.identifier }.filter { $0.hasPrefix(identifierPrefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        // A check-in that already showed has done its job; clear it so nothing piles up.
        let delivered = await center.deliveredNotifications()
        let shown = delivered.map { $0.request.identifier }.filter { $0.hasPrefix(identifierPrefix) }
        if !shown.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: shown)
        }

        guard isEnabled else { return }

        // Never prompts here. Settings asks once, when the person turns the check-in on.
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            log.info("Notifications are off; no check-ins scheduled")
            return
        }

        let calendar = Calendar.current
        let dates = upcomingFireDates(
            after: now,
            minutes: chosenMinutes,
            restChosenAt: restChosenAt,
            count: scheduledCount,
            calendar: calendar
        )

        for date in dates {
            let copy = message(for: date, calendar: calendar)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default
            content.categoryIdentifier = NotificationCategory.dailyCheckIn
            content.threadIdentifier = NotificationCategory.dailyCheckIn

            // Wall-clock components with no time zone: the check-in follows the person when
            // they travel, and keeps its time across daylight-saving changes.
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let request = UNNotificationRequest(
                identifier: identifier(for: date, calendar: calendar),
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
            } catch {
                log.error("Could not schedule a check-in: \(String(describing: error), privacy: .public)")
            }
        }
        log.info("Scheduled \(dates.count, privacy: .public) check-ins")
    }

    // MARK: - Pure helpers

    /// Keeps a stored time inside one day (0 ... 23:59).
    nonisolated static func clampedMinutes(_ minutes: Int) -> Int {
        min(max(minutes, 0), 24 * 60 - 1)
    }

    /// 540 → (9, 0). Out-of-range values are clamped to the same day.
    nonisolated static func hourAndMinute(fromMinutes minutes: Int) -> (hour: Int, minute: Int) {
        let clamped = clampedMinutes(minutes)
        return (clamped / 60, clamped % 60)
    }

    /// The minutes after midnight of `date`'s wall-clock time in `calendar`.
    nonisolated static func minutesAfterMidnight(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return clampedMinutes((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
    }

    /// The chosen time on the day `day` falls on, for a time picker. Falls back to `day`.
    nonisolated static func pickerDate(forMinutes minutes: Int, on day: Date, calendar: Calendar) -> Date {
        let time = hourAndMinute(fromMinutes: minutes)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day) ?? day
    }

    /// The next `count` check-in times after `now`, one per day at `minutes` after midnight.
    ///
    /// - Today is included only while its time is still ahead and the person didn't let
    ///   today rest (`restChosenAt` on the same day).
    /// - Each date is built in `calendar` (and its time zone), so the wall-clock time holds
    ///   across daylight-saving changes. On a day that skips the chosen time (spring forward),
    ///   the check-in comes at the next valid time that day.
    nonisolated static func upcomingFireDates(
        after now: Date,
        minutes: Int,
        restChosenAt: Date?,
        count: Int = 7,
        calendar: Calendar
    ) -> [Date] {
        guard count > 0 else { return [] }

        let time = hourAndMinute(fromMinutes: minutes)
        let startOfToday = calendar.startOfDay(for: now)
        let restingToday = restChosenAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false

        var dates: [Date] = []
        // A few spare days, only in case a calendar can't build a date.
        for offset in 0..<(count + 7) {
            if dates.count == count { break }
            if offset == 0 && restingToday { continue }

            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  let fire = fireDate(hour: time.hour, minute: time.minute, on: day, calendar: calendar),
                  fire > now else { continue }

            // Never two on one day (possible only with unusual calendars).
            if let last = dates.last, calendar.isDate(last, inSameDayAs: fire) { continue }
            dates.append(fire)
        }
        return dates
    }

    /// The wall-clock time on `day`. If the calendar can't set it directly, builds it from
    /// components instead, which moves a skipped time forward rather than dropping the day.
    private nonisolated static func fireDate(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date? {
        if let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) {
            return date
        }
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = minute
        parts.second = 0
        return calendar.date(from: parts)
    }

    /// `checkin-2026-10-09`: one id per day, so rescheduling replaces rather than duplicates.
    nonisolated static func identifier(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let month = parts.month ?? 0
        let day = parts.day ?? 0
        return identifierPrefix + String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Gentle, rotating words. The same day always gets the same words.
    nonisolated static func message(for date: Date, calendar: Calendar) -> (title: String, body: String) {
        let index = (calendar.ordinality(of: .day, in: .era, for: date) ?? 0) % messages.count
        return messages[index]
    }

    nonisolated static let messages: [(title: String, body: String)] = [
        ("Want a gentle check-in?", "Today is here when you are. One small thing is plenty."),
        ("How’s today feeling?", "You can set your energy and see one thing to start with."),
        ("A quiet moment to plan, if you want one.", "Open Today and pick one small step."),
        ("Checking in, softly.", "Just what fits today, nothing more."),
        ("Here if you want a hand.", "Take a look at today, at your own pace.")
    ]
}
