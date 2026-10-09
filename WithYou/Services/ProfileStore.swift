//
//  ProfileStore.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

struct ProfileStore {
    static func appState(in context: ModelContext) -> AppState {
        let descriptor = FetchDescriptor<AppState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let s = AppState()
        context.insert(s)
        try? context.save()
        return s
    }

    static func activeProfile(in context: ModelContext) -> UserProfile? {
        let state = appState(in: context)
        guard let id = state.activeProfileId else { return nil }

        let descriptor = FetchDescriptor<UserProfile>(
            predicate: #Predicate { $0.id == id }
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Makes sure there is always a usable active profile:
    /// - no profiles at all → creates "Me" and makes it active;
    /// - no active id, or an id that matches no profile (it was deleted) → uses the oldest profile.
    static func ensureDefaultProfile(in context: ModelContext) {
        let all = (try? context.fetch(
            FetchDescriptor<UserProfile>(
                sortBy: [SortDescriptor<UserProfile>(\.createdAt, order: .forward)]
            )
        )) ?? []
        let state = appState(in: context)

        guard let first = all.first else {
            let p = UserProfile(name: "Me")
            context.insert(p)
            state.activeProfileId = p.id
            try? context.save()
            return
        }

        if let id = state.activeProfileId, all.contains(where: { $0.id == id }) {
            return
        }

        state.activeProfileId = first.id
        try? context.save()
    }

    /// Deletes a profile together with its focus presets, then repairs the active profile
    /// so nothing points at a profile that no longer exists.
    static func deleteProfile(_ profile: UserProfile, in context: ModelContext) {
        FocusPresetStore.deleteAll(for: profile.id, in: context)
        context.delete(profile)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (deleteProfile):", error)
        }
        ensureDefaultProfile(in: context)
    }
}
