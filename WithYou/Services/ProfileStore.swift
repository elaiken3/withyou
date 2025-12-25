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

    static func ensureDefaultProfile(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
        let state = appState(in: context)

        if all.isEmpty {
            let p = UserProfile(name: "Me")
            context.insert(p)
            state.activeProfileId = p.id
            try? context.save()
        } else if state.activeProfileId == nil {
            state.activeProfileId = all.first?.id
            try? context.save()
        }
    }
}

