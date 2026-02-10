//
//  CompletionStore.swift
//  WithYou
//
//  Created by Codex on 2/10/26.
//

import Foundation
import SwiftData

struct CompletionStore {
    static func completeFromSession(_ session: FocusSession, in context: ModelContext) {
        // 1) Prevent duplicates
        if session.completedLoggedAt != nil { return }
        session.completedLoggedAt = Date()

        // 2) Clear source item
        if let kindRaw = session.sourceKindRaw,
           let kind = FocusSourceKind(rawValue: kindRaw),
           let sourceId = session.sourceId {

            switch kind {
            case .inbox:
                // find inbox item and delete it
                let descriptor = FetchDescriptor<InboxItem>()
                if let item = (try? context.fetch(descriptor))?.first(where: { $0.id == sourceId }) {
                    context.delete(item)
                }

            case .reminder:
                let descriptor = FetchDescriptor<VerboseReminder>()
                if let r = (try? context.fetch(descriptor))?.first(where: { $0.id == sourceId }) {
                    NotificationManager.shared.cancelReminder(id: r.id)
                    r.isDone = true
                    // optional: also delete if you don't want done reminders hanging around
                    // context.delete(r)
                }
            }
        }

        // 3) End session so it disappears from “Right now”
        session.isActive = false
        if session.endedAt == nil {
            session.endedAt = Date()
        }

        do {
            try context.save()
        } catch {
            print("❌ Save failed (completeFromSession):", error)
        }
    }

    static func completeInboxItem(_ item: InboxItem, in context: ModelContext) {
        let session = FocusSession(
            focusTitle: item.title,
            focusStartStep: item.startStep,
            durationSeconds: 0,
            createdAt: Date(),
            startedAt: nil,
            endedAt: Date(),
            isActive: false,
            completedLoggedAt: Date(),
            sourceKindRaw: FocusSourceKind.inbox.rawValue,
            sourceId: item.id
        )
        context.insert(session)
        context.delete(item)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (completeInboxItem):", error)
        }
    }

    static func completeReminder(_ reminder: VerboseReminder, in context: ModelContext) {
        let session = FocusSession(
            focusTitle: reminder.title,
            focusStartStep: reminder.startStep,
            durationSeconds: 0,
            createdAt: Date(),
            startedAt: nil,
            endedAt: Date(),
            isActive: false,
            completedLoggedAt: Date(),
            sourceKindRaw: FocusSourceKind.reminder.rawValue,
            sourceId: reminder.id
        )
        context.insert(session)

        NotificationManager.shared.cancelReminder(id: reminder.id)
        reminder.isDone = true
        do {
            try context.save()
        } catch {
            print("❌ Save failed (completeReminder):", error)
        }
    }
}
