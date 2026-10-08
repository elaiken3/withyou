//
//  ReminderStore.swift
//  WithYou
//
//  Created by Codex on 2/10/26.
//

import Foundation
import SwiftData

/// All reminder creation, rescheduling and letting-go goes through here so the
/// notification always matches the saved reminder.
enum ReminderStore {

    // MARK: - Copy

    /// Notification body for a reminder. Kept in one place so every path uses the same words.
    /// `.firm` is shorter and more direct — never louder, never guilt-based.
    static func notificationBody(startStep: String, estimateMinutes: Int, tone: ReminderTone = .gentle) -> String {
        let step = startStep.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (tone, step.isEmpty) {
        case (.gentle, true):
            return "Want help starting? Tap “Help me start”."
        case (.gentle, false):
            return """
            Start: \(step) (\(estimateMinutes) min)
            Tap “Help me start” if you’re stuck.
            """
        case (.firm, true):
            return "Time to start. “Help me start” is here if you need it."
        case (.firm, false):
            return "First step: \(step). \(estimateMinutes) min."
        }
    }

    // MARK: - Create

    @MainActor
    static func createAndSchedule(
        title: String,
        startStep: String,
        estimateMinutes: Int,
        scheduledAt: Date,
        in context: ModelContext
    ) async throws -> VerboseReminder {
        let reminder = VerboseReminder(
            title: title,
            startStep: startStep,
            estimateMinutes: estimateMinutes,
            scheduledAt: scheduledAt
        )

        context.insert(reminder)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (createAndSchedule):", error)
            throw error
        }

        // Asking for permission here (the first time something is scheduled) is
        // gentler than prompting at launch, and it fixes release builds that never asked.
        await NotificationManager.shared.ensureAuthorization()
        refreshNotification(for: reminder)

        return reminder
    }

    // MARK: - Change

    /// Moves a reminder to `date`, saves, and replaces its pending notification.
    static func reschedule(_ reminder: VerboseReminder, to date: Date, in context: ModelContext) throws {
        reminder.scheduledAt = date
        reminder.lastCheckedAt = nil
        reminder.isDone = false
        try context.save()
        refreshNotification(for: reminder)
    }

    /// Re-sends the notification after the title, step or time changed. Saves first.
    static func saveEdits(_ reminder: VerboseReminder, in context: ModelContext) throws {
        try context.save()
        refreshNotification(for: reminder)
    }

    /// "Not needed" — removes the reminder and its pending notification. No record, no guilt.
    static func letGo(_ reminder: VerboseReminder, in context: ModelContext) throws {
        NotificationManager.shared.cancelReminder(id: reminder.id)
        context.delete(reminder)
        try context.save()
    }

    // MARK: - Notifications

    /// Schedules (or replaces) the local notification for `reminder`.
    ///
    /// Reads the reminder synchronously (call it where you already use the model, e.g. on
    /// the main actor for UI code) and hands only plain values to the async work.
    /// Past times are skipped: a calendar trigger in the past never fires, and the Today
    /// screen's "Still relevant?" card already handles reminders whose time has passed.
    static func refreshNotification(for reminder: VerboseReminder) {
        let id = reminder.id
        let title = reminder.title
        let tone = reminder.modelContext.flatMap { ProfileStore.activeProfile(in: $0) }?.tone ?? .gentle
        let body = notificationBody(startStep: reminder.startStep, estimateMinutes: reminder.estimateMinutes, tone: tone)
        let when = reminder.scheduledAt

        NotificationManager.shared.cancelReminder(id: id)
        guard !reminder.isDone, when > Date() else { return }

        Task {
            do {
                try await NotificationManager.shared.scheduleReminder(
                    id: id,
                    title: title,
                    body: body,
                    scheduledAt: when
                )
            } catch {
                print("❌ Notification schedule failed:", error)
            }
        }
    }

    // MARK: - Time helpers

    /// Tomorrow at the profile's morning hour (default 9).
    static func nextMorning(profile: UserProfile?, after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return calendar.date(bySettingHour: profile?.morningHour ?? 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    /// Today at the profile's evening hour (default 19), or nil if that time has passed.
    static func thisEvening(profile: UserProfile?, now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        guard let evening = calendar.date(
            bySettingHour: profile?.eveningHour ?? 19, minute: 0, second: 0, of: now
        ) else { return nil }
        return evening > now ? evening : nil
    }

    /// Rounds `date` up to the next 5-minute mark so suggested times read naturally.
    static func roundedUp(_ date: Date) -> Date {
        let calendar = Calendar.current
        let minute = calendar.component(.minute, from: date)
        let remainder = minute % 5
        let bumped = remainder == 0 ? date : date.addingTimeInterval(TimeInterval((5 - remainder) * 60))
        return calendar.date(bySetting: .second, value: 0, of: bumped) ?? bumped
    }
}
