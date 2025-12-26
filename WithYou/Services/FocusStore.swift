//
//  FocusStore.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData

struct FocusSessionStore {
    static func activeSession(in context: ModelContext) -> FocusSession? {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            },
            sortBy: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor))?.first
    }

    /// Optional hardening: if multiple sessions are active, keep newest and end the rest.
    static func normalizeActiveSessions(in context: ModelContext) {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            },
            sortBy: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )

        guard let active = try? context.fetch(descriptor), active.count > 1 else { return }

        for s in active.dropFirst() {
            s.isActive = false
            s.endedAt = Date()
        }
        try? context.save()
    }
}

