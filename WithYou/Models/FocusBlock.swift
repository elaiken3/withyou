//
//  FocusBlock.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/26/25.
//

import Foundation
import SwiftData

@Model
final class FocusBlock {
    var id: UUID
    var createdAt: Date
    var scheduledAt: Date
    var title: String
    var startStep: String
    var durationSeconds: Int
    var isCompleted: Bool

    init(
        scheduledAt: Date,
        title: String,
        startStep: String,
        durationSeconds: Int,
        createdAt: Date = Date(),
        isCompleted: Bool = false
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.scheduledAt = scheduledAt
        self.title = title
        self.startStep = startStep
        self.durationSeconds = durationSeconds
        self.isCompleted = isCompleted
    }
}
