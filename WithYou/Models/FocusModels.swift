//
//  FocusModels.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

@Model
final class FocusSession {
    var id: UUID
    var createdAt: Date
    var focusTitle: String
    var focusStartStep: String
    var durationSeconds: Int
    var startedAt: Date?
    var endedAt: Date?
    var isActive: Bool

    // NEW: persist pause across app restarts
    var pausedSeconds: Int
    var pausedAt: Date?

    init(
        focusTitle: String,
        focusStartStep: String = "",
        durationSeconds: Int,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        isActive: Bool = true,
        pausedSeconds: Int = 0,
        pausedAt: Date? = nil
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.focusTitle = focusTitle
        self.focusStartStep = focusStartStep
        self.durationSeconds = durationSeconds
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.isActive = isActive
        self.pausedSeconds = pausedSeconds
        self.pausedAt = pausedAt
    }
}
@Model
final class FocusDumpItem {
    var id: UUID
    var createdAt: Date
    var text: String
    var sessionId: UUID

    init(text: String, sessionId: UUID, createdAt: Date = Date()) {
        self.id = UUID()
        self.createdAt = createdAt
        self.text = text
        self.sessionId = sessionId
    }
}


