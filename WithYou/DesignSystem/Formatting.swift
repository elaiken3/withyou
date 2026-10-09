//
//  Formatting.swift
//  WithYou
//

import Foundation

extension Date {
    /// "7:00 PM" (or "19:00"), following the user's locale and 12/24-hour setting.
    var timeText: String {
        formatted(date: .omitted, time: .shortened)
    }

    /// "today at 7:00 PM", "tomorrow at 9:00 AM", "Mar 12 at 9:00 AM".
    var friendlyDayTime: String {
        "\(relativeDayText) at \(timeText)"
    }

    /// "today", "tomorrow", "yesterday", or "Mar 12".
    var relativeDayText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "today" }
        if calendar.isDateInTomorrow(self) { return "tomorrow" }
        if calendar.isDateInYesterday(self) { return "yesterday" }
        return formatted(.dateTime.month(.abbreviated).day())
    }

    /// Section header for a day: "Today", "Tomorrow", "Thursday, Oct 9" (year added when not this year).
    var dayHeaderText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return "Today" }
        if calendar.isDateInTomorrow(self) { return "Tomorrow" }
        if calendar.isDate(self, equalTo: Date(), toGranularity: .year) {
            return formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        }
        return formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }
}

/// "9 AM" style label for an hour-of-day setting.
func hourLabel(_ hour: Int) -> String {
    var components = DateComponents()
    components.hour = hour
    components.minute = 0
    guard let date = Calendar.current.date(from: components) else { return "\(hour):00" }
    return date.formatted(.dateTime.hour())
}
