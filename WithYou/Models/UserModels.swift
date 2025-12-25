//
//  UserModels.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

enum ReminderTone: String, Codable {
    case gentle
    case firm
}

@Model
final class UserProfile {
    var id: UUID
    var createdAt: Date

    var name: String
    var toneRaw: String

    var morningHour: Int
    var afternoonHour: Int
    var eveningHour: Int
    var defaultFocusMinutes: Int

    var defaultMantra: String
    var routeSiriToFocusDumpWhenActive: Bool

    init(name: String,
         tone: ReminderTone = .gentle,
         morningHour: Int = 9,
         afternoonHour: Int = 13,
         eveningHour: Int = 19,
         defaultFocusMinutes: Int = 45,
         defaultMantra: String = "I am here now.",
         routeSiriToFocusDumpWhenActive: Bool = true) {
        self.id = UUID()
        self.createdAt = Date()
        self.name = name
        self.toneRaw = tone.rawValue
        self.morningHour = morningHour
        self.afternoonHour = afternoonHour
        self.eveningHour = eveningHour
        self.defaultFocusMinutes = defaultFocusMinutes
        self.defaultMantra = defaultMantra
        self.routeSiriToFocusDumpWhenActive = routeSiriToFocusDumpWhenActive
    }

    var tone: ReminderTone {
        get { ReminderTone(rawValue: toneRaw) ?? .gentle }
        set { toneRaw = newValue.rawValue }
    }
}

@Model
final class AppState {
    var id: UUID
    var activeProfileId: UUID?

    init(activeProfileId: UUID? = nil) {
        self.id = UUID()
        self.activeProfileId = activeProfileId
    }
}
