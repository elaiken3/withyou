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

    /// Removes one preset and saves.
    static func delete(_ preset: FocusDurationPreset, in context: ModelContext) {
        context.delete(preset)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (delete preset):", error)
        }
    }

    /// Removes every preset that belongs to `profileId` (used when a profile is deleted).
    /// Does not save; the caller saves once with its other changes.
    static func deleteAll(for profileId: UUID, in context: ModelContext) {
        for preset in presets(for: profileId, in: context) {
            context.delete(preset)
        }
    }
}
