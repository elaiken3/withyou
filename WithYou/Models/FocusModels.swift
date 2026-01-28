//
//  FocusModels.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

enum FocusSourceKind: String {
    case inbox
    case reminder
}

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
    var completedLoggedAt: Date?

    /// Links this focus session back to the thing it came from (Inbox or Reminder).
    var sourceKindRaw: String?   // "inbox" | "reminder"
    var sourceId: UUID?

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
        pausedAt: Date? = nil,
        completedLoggedAt: Date? = nil,
        sourceKindRaw: String? = nil,
        sourceId: UUID? = nil
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
        self.completedLoggedAt = completedLoggedAt
        self.sourceKindRaw = sourceKindRaw
        self.sourceId = sourceId
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

