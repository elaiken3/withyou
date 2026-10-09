//
//  EnergyCheckIn.swift
//  WithYou
//

import Foundation

/// Today's optional energy check-in, as Today stores it: the level (`@AppStorage("todayEnergyLevel")`)
/// plus the day it was set (`@AppStorage("todayEnergyDay")`), so it quietly resets each morning.
enum EnergyCheckIn {
    /// The stored value for the day `date` falls on.
    static func dayValue(for date: Date, calendar: Calendar = .current) -> Double {
        calendar.startOfDay(for: date).timeIntervalSinceReferenceDate
    }

    /// The level the person picked today, or nil when they didn't (or picked it on another day).
    /// AI requests send nil rather than guessing.
    static func level(raw: String, day: Double, on date: Date, calendar: Calendar = .current) -> EnergyLevel? {
        guard day == dayValue(for: date, calendar: calendar) else { return nil }
        return EnergyLevel(rawValue: raw)
    }
}
