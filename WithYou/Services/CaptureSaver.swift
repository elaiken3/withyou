//
//  CaptureSaver.swift
//  WithYou
//
//  Saves capture suggestions the person reviewed (or asked Siri to save):
//  ones with a time become scheduled reminders, the rest go to the Inbox.
//

import Foundation
import SwiftData

/// What one save created: for the confirmation line, and so Undo can remove exactly that.
struct CaptureSaveSummary: Equatable {
    var inboxItemIds: [UUID] = []
    var reminderIds: [UUID] = []
    var scheduledDates: [Date] = []

    var inboxCount: Int { inboxItemIds.count }
    var scheduledCount: Int { reminderIds.count }
    var totalCount: Int { inboxCount + scheduledCount }
    var firstScheduledAt: Date? { scheduledDates.min() }
}

enum CaptureSaver {

    /// Creates the reminder for one timed suggestion and returns its id.
    /// Tests pass their own so nothing asks for notification permission.
    typealias ReminderScheduler = @MainActor (CaptureSuggestion, Date, ModelContext) async throws -> UUID

    /// Titles typed in review can be longer than suggested ones, but not endless.
    static let titleLimit = 200

    // MARK: - Save

    static func save(
        _ items: [CaptureSuggestion],
        source: ItemSource,
        in context: ModelContext
    ) async throws -> CaptureSaveSummary {
        try await save(items, source: source, in: context, now: Date()) { item, date, modelContext in
            let reminder = try await ReminderStore.createAndSchedule(
                title: item.title,
                startStep: item.firstStep,
                estimateMinutes: item.estimateMinutes,
                scheduledAt: date,
                in: modelContext
            )
            return reminder.id
        }
    }

    /// All or nothing: if anything fails, whatever this call already created is removed
    /// again before the error is thrown, so trying again never makes doubles.
    static func save(
        _ items: [CaptureSuggestion],
        source: ItemSource,
        in context: ModelContext,
        now: Date,
        scheduler: ReminderScheduler
    ) async throws -> CaptureSaveSummary {
        let ready = items.compactMap { prepared($0) }
        var summary = CaptureSaveSummary()

        // Inbox items first, in one save. The Inbox lists newest first, so each later item
        // is a millisecond "older" and they read in the order they were said.
        var inserted: [InboxItem] = []
        for item in ready where item.scheduledAt == nil {
            let inbox = InboxItem(
                content: item.originalText,
                title: item.title,
                createdAt: now.addingTimeInterval(-Double(inserted.count) * 0.001),
                source: source,
                startStep: item.firstStep,
                estimateMinutes: item.estimateMinutes
            )
            context.insert(inbox)
            inserted.append(inbox)
        }
        if !inserted.isEmpty {
            do {
                try context.save()
            } catch {
                for inbox in inserted {
                    context.delete(inbox)
                }
                throw error
            }
            summary.inboxItemIds = inserted.map { $0.id }
        }

        for item in ready {
            guard let when = item.scheduledAt else { continue }
            do {
                let id = try await scheduler(item, when, context)
                summary.reminderIds.append(id)
                summary.scheduledDates.append(when)
            } catch {
                undo(summary, in: context)
                throw error
            }
        }

        return summary
    }

    /// Tidies one suggestion for saving, or nil when there's nothing to save.
    static func prepared(_ suggestion: CaptureSuggestion) -> CaptureSuggestion? {
        var item = suggestion
        let original = item.originalText.trimmingCharacters(in: .whitespacesAndNewlines)

        var title = singleLine(item.title)
        if title.isEmpty {
            title = String(singleLine(original).prefix(80))
        }
        title = String(title.prefix(titleLimit)).trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return nil }

        item.title = title
        item.firstStep = singleLine(item.firstStep)
        item.estimateMinutes = min(max(item.estimateMinutes, 1), 240)
        item.originalText = original.isEmpty ? title : original
        return item
    }

    private static func singleLine(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - Undo

    /// Removes everything `summary` created (Undo, or a save that failed partway).
    static func undo(_ summary: CaptureSaveSummary, in context: ModelContext) {
        var removedInboxItem = false
        for id in summary.inboxItemIds {
            var descriptor = FetchDescriptor<InboxItem>(
                predicate: #Predicate<InboxItem> { (item: InboxItem) in item.id == id }
            )
            descriptor.fetchLimit = 1
            if let item = (try? context.fetch(descriptor))?.first {
                context.delete(item)
                removedInboxItem = true
            }
        }
        if removedInboxItem {
            try? context.save()
        }

        for id in summary.reminderIds {
            var descriptor = FetchDescriptor<VerboseReminder>(
                predicate: #Predicate<VerboseReminder> { (reminder: VerboseReminder) in reminder.id == id }
            )
            descriptor.fetchLimit = 1
            if let reminder = (try? context.fetch(descriptor))?.first {
                // Cancels the pending notification too.
                try? ReminderStore.letGo(reminder, in: context)
            } else {
                NotificationManager.shared.cancelReminder(id: id)
            }
        }
    }

    // MARK: - Words

    /// "Saved 3 things to your Inbox.", "Scheduled for tomorrow at 9:00 AM.", …
    /// Used for Siri's answer and for the toast after a review.
    static func message(for summary: CaptureSaveSummary) -> String {
        let inbox = summary.inboxCount
        let scheduled = summary.scheduledCount
        let when = summary.firstScheduledAt?.friendlyDayTime ?? ""

        switch (inbox, scheduled) {
        case (0, 0):
            return "There was nothing to save."
        case (1, 0):
            return "Saved to your Inbox."
        case (_, 0):
            return "Saved \(inbox) things to your Inbox."
        case (0, 1):
            return "Scheduled for \(when)."
        case (0, _):
            return "Scheduled \(scheduled) things, starting \(when)."
        case (_, 1):
            return "Saved \(things(inbox)) to your Inbox and scheduled 1 for \(when)."
        default:
            return "Saved \(things(inbox)) to your Inbox and scheduled \(scheduled), starting \(when)."
        }
    }

    private static func things(_ count: Int) -> String {
        count == 1 ? "1 thing" : "\(count) things"
    }

    // MARK: - Suggestions

    /// The rule-based reading of `text` as one item. Used when AI isn't available or is slow.
    static func rulesSuggestions(for text: String, profile: UserProfile?, now: Date = Date()) -> [CaptureSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parsed = CaptureParser().parse(trimmed, profile: profile, now: now)
        return [
            CaptureSuggestion(
                title: parsed.title,
                firstStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes,
                scheduledAt: parsed.scheduledAt,
                originalText: trimmed
            )
        ]
    }

    /// AI suggestions for `text`, or the rule-based reading if AI takes longer than `seconds`.
    /// Siri is waiting for an answer, so it can't sit through a slow network.
    static func suggestions(for text: String, profile: UserProfile?, within seconds: Double) async -> [CaptureSuggestion] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let captureContext = CaptureContext.current(profile: profile)
        let result = await firstResult(within: seconds) {
            await AIService.capture(trimmed, context: captureContext)
        }
        if let items = result?.value, !items.isEmpty {
            return items
        }
        return rulesSuggestions(for: trimmed, profile: profile)
    }

    /// Runs `operation`, but stops waiting after `seconds` and returns nil.
    /// At the deadline the operation is cancelled; anything it returns later is ignored.
    static func firstResult<T>(within seconds: Double, _ operation: @escaping @MainActor () async -> T) async -> T? {
        let box = DeadlineBox<T>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            box.continuation = continuation
            let work = Task { @MainActor in
                let value = await operation()
                box.finish(value)
            }
            box.timer = Task { @MainActor in
                try? await Task.sleep(for: .seconds(seconds))
                work.cancel()
                box.finish(nil)
            }
        }
        return box.value
    }
}

/// Whichever finishes first (the work or the deadline) resumes the waiting caller, once.
private final class DeadlineBox<T> {
    var value: T?
    var continuation: CheckedContinuation<Void, Never>?
    var timer: Task<Void, Never>?

    func finish(_ result: T?) {
        guard let continuation else { return }
        self.continuation = nil
        value = result
        timer?.cancel()
        continuation.resume()
    }
}
