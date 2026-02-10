//
//  Models.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

enum ItemSource: String, Codable {
    case siri
    case app
    case widget
}

@Model
final class InboxItem {
    var id: UUID
    var content: String
    var title: String
    var createdAt: Date
    var sourceRaw: String

    var startStep: String
    var estimateMinutes: Int
    
    var sortIndex: Int?

    init(content: String,
         title: String,
         createdAt: Date = Date(),
         source: ItemSource,
         startStep: String,
         estimateMinutes: Int = 3,
         sortIndex: Int? = nil
    )
    {
        self.id = UUID()
        self.content = content
        self.title = title
        self.createdAt = createdAt
        self.sourceRaw = source.rawValue
        self.startStep = startStep
        self.estimateMinutes = estimateMinutes
        self.sortIndex = sortIndex
    }

    var source: ItemSource {
        get { ItemSource(rawValue: sourceRaw) ?? .app }
        set { sourceRaw = newValue.rawValue }
    }
}

@Model
final class VerboseReminder {
    var id: UUID
    var title: String
    var why: String
    var startStep: String
    var estimateMinutes: Int
    var scheduledAt: Date
    var createdAt: Date

    var isStarted: Bool
    var isDone: Bool
    
    var lastCheckedAt: Date?

    init(title: String,
         why: String = "",
         startStep: String,
         estimateMinutes: Int = 5,
         scheduledAt: Date,
         createdAt: Date = Date(),
         isStarted: Bool = false,
         isDone: Bool = false,
         lastCheckedAt: Date? = nil
    )
    {
        self.id = UUID()
        self.title = title
        self.why = why
        self.startStep = startStep
        self.estimateMinutes = estimateMinutes
        self.scheduledAt = scheduledAt
        self.createdAt = createdAt
        self.isStarted = isStarted
        self.isDone = isDone
        self.lastCheckedAt = lastCheckedAt
    }
}
