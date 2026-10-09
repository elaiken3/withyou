//
//  CompletionStore.swift
//  WithYou
//
//  Created by Codex on 2/10/26.
//

import Foundation
import SwiftData

/// Finishing things: focus sessions, Inbox items and reminders, plus moving
/// brain-dump thoughts somewhere safe so nothing parked during a session is lost.
struct CompletionStore {

    // MARK: - Focus sessions

    /// "I finished it." Logs the session as completed, clears its source (the Inbox item is
    /// removed, the reminder is marked done), ends the session and cancels its
    /// "Focus time is up" notification. Safe to call more than once.
    static func completeFromSession(_ session: FocusSession, in context: ModelContext) {
        if session.completedLoggedAt == nil {
            session.completedLoggedAt = Date()
            clearSource(of: session, in: context)
        }

        close(session)

        do {
            try context.save()
        } catch {
            print("❌ Save failed (completeFromSession):", error)
        }
    }

    /// "Stopping for now." Ends the session without completing it: the source Inbox item
    /// or reminder stays exactly where it was, and the end notification is cancelled.
    static func endWithoutCompleting(_ session: FocusSession, in context: ModelContext) {
        close(session)

        do {
            try context.save()
        } catch {
            print("❌ Save failed (endWithoutCompleting):", error)
        }
    }

    /// Marks the session ended, folds any running pause into `pausedSeconds`,
    /// and cancels its pending end notification. Does not save.
    private static func close(_ session: FocusSession) {
        NotificationManager.shared.cancelFocusEnd(sessionId: session.id)

        let now = Date()
        if let pausedAt = session.pausedAt {
            session.pausedSeconds += max(0, Int(now.timeIntervalSince(pausedAt)))
            session.pausedAt = nil
        }

        session.isActive = false
        if session.endedAt == nil {
            session.endedAt = now
        }
    }

    /// Removes the Inbox item or marks the reminder done for a completed session. Does not save.
    private static func clearSource(of session: FocusSession, in context: ModelContext) {
        guard let kindRaw = session.sourceKindRaw,
              let kind = FocusSourceKind(rawValue: kindRaw),
              let sourceId = session.sourceId else { return }

        switch kind {
        case .inbox:
            var descriptor = FetchDescriptor<InboxItem>(
                predicate: #Predicate<InboxItem> { (item: InboxItem) in
                    item.id == sourceId
                }
            )
            descriptor.fetchLimit = 1
            if let item = (try? context.fetch(descriptor))?.first {
                context.delete(item)
            }

        case .reminder:
            var descriptor = FetchDescriptor<VerboseReminder>(
                predicate: #Predicate<VerboseReminder> { (reminder: VerboseReminder) in
                    reminder.id == sourceId
                }
            )
            descriptor.fetchLimit = 1
            if let reminder = (try? context.fetch(descriptor))?.first {
                NotificationManager.shared.cancelReminder(id: reminder.id)
                reminder.isDone = true
            }
        }
    }

    // MARK: - Inbox items and reminders

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

    // MARK: - Brain-dump thoughts

    /// What a parked thought becomes in the Inbox.
    struct ThoughtFields: Equatable {
        var title: String
        var startStep: String
        var estimateMinutes: Int
    }

    /// A tidied title and first step when AI made them (see `FocusReviewView`), otherwise the
    /// parser's. The estimate always comes from the parser.
    static func inboxFields(parsed: ParsedCapture, tidy: TidyItem?) -> ThoughtFields {
        if let tidy {
            let title = tidy.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let step = tidy.firstStep.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                return ThoughtFields(
                    title: title,
                    startStep: step.isEmpty ? parsed.startStep : step,
                    estimateMinutes: parsed.estimateMinutes
                )
            }
        }
        return ThoughtFields(title: parsed.title, startStep: parsed.startStep, estimateMinutes: parsed.estimateMinutes)
    }

    /// Turns each thought into an Inbox item and removes the thought. Does not save.
    /// The title and first step come from `tidied` (keyed by thought id) when present, else
    /// from `CaptureParser`; the original words are always kept as the item's `content`.
    static func moveThoughtsToInbox(
        _ items: [FocusDumpItem],
        tidied: [UUID: TidyItem] = [:],
        in context: ModelContext
    ) {
        guard !items.isEmpty else { return }
        let parser = CaptureParser()
        let profile = ProfileStore.activeProfile(in: context)

        for item in items {
            let text = item.text
            let fields = inboxFields(parsed: parser.parse(text, profile: profile), tidy: tidied[item.id])
            let inboxItem = InboxItem(
                content: text,
                title: fields.title,
                source: .app,
                startStep: fields.startStep,
                estimateMinutes: fields.estimateMinutes
            )
            context.insert(inboxItem)
            context.delete(item)
        }
    }

    /// Moves every thought still parked in `session` to the Inbox and saves.
    /// Returns how many moved.
    @discardableResult
    static func moveLeftoverThoughtsToInbox(
        for session: FocusSession,
        tidied: [UUID: TidyItem] = [:],
        in context: ModelContext
    ) -> Int {
        let sessionId = session.id
        let descriptor = FetchDescriptor<FocusDumpItem>(
            predicate: #Predicate<FocusDumpItem> { (item: FocusDumpItem) in
                item.sessionId == sessionId
            },
            sortBy: [SortDescriptor<FocusDumpItem>(\.createdAt, order: .forward)]
        )
        let items = (try? context.fetch(descriptor)) ?? []
        guard !items.isEmpty else { return 0 }

        moveThoughtsToInbox(items, tidied: tidied, in: context)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (moveLeftoverThoughtsToInbox):", error)
        }
        return items.count
    }

    /// Thoughts can be left behind when a session ends without a wrap-up (another session
    /// was started elsewhere, or the app closed on the wrap-up screen). This moves thoughts
    /// whose session is no longer active into the Inbox, skipping `keepingSessionId`
    /// (the session currently being wrapped up). Returns how many moved.
    @discardableResult
    static func rescueOrphanedThoughts(keepingSessionId: UUID? = nil, in context: ModelContext) -> Int {
        let allThoughts = (try? context.fetch(
            FetchDescriptor<FocusDumpItem>(
                sortBy: [SortDescriptor<FocusDumpItem>(\.createdAt, order: .forward)]
            )
        )) ?? []
        guard !allThoughts.isEmpty else { return 0 }

        let activeDescriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            }
        )
        let activeIds = Set(((try? context.fetch(activeDescriptor)) ?? []).map { $0.id })

        let orphans = allThoughts.filter { item in
            !activeIds.contains(item.sessionId) && item.sessionId != keepingSessionId
        }
        guard !orphans.isEmpty else { return 0 }

        moveThoughtsToInbox(orphans, in: context)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (rescueOrphanedThoughts):", error)
        }
        return orphans.count
    }
}
