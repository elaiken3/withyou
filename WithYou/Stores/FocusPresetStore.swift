//
//  FocusPresetStore.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/29/25.
//

import Foundation
import SwiftData

struct FocusPresetStore {
    static func presets(for profileId: UUID, in context: ModelContext) -> [FocusDurationPreset] {
        let descriptor = FetchDescriptor<FocusDurationPreset>(
            predicate: #Predicate<FocusDurationPreset> { p in
                p.profileId == profileId
            },
            sortBy: [
                SortDescriptor(\.sortOrder, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    static func nextSortOrder(for profileId: UUID, in context: ModelContext) -> Int {
        let existing = presets(for: profileId, in: context)
        return (existing.map(\.sortOrder).max() ?? 0) + 1
    }

    static func addPreset(minutes: Int, label: String, profileId: UUID, in context: ModelContext) {
        let sort = nextSortOrder(for: profileId, in: context)
        let preset = FocusDurationPreset(minutes: minutes, label: label, sortOrder: sort, profileId: profileId)
        context.insert(preset)
        try? context.save()
    }
}
