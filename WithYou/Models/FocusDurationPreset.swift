//
//  FocusDurationPreset.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/29/25.
//

import Foundation
import SwiftData

@Model
final class FocusDurationPreset {
    var id: UUID
    var createdAt: Date
    var minutes: Int
    var label: String
    var sortOrder: Int
    var profileId: UUID

    init(
        minutes: Int,
        label: String,
        sortOrder: Int,
        profileId: UUID,
        createdAt: Date = Date()
    ) {
        self.id = UUID()
        self.createdAt = createdAt
        self.minutes = minutes
        self.label = label
        self.sortOrder = sortOrder
        self.profileId = profileId
    }
}
