//
//  ReminderStore.swift
//  WithYou
//
//  Created by Codex on 2/10/26.
//

import Foundation
import SwiftData

enum ReminderStore {
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

        let body =
        """
        Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)
        Tap “Help me start” if you’re stuck.
        """

        do {
            try await NotificationManager.shared.scheduleReminder(
                id: reminder.id,
                title: reminder.title,
                body: body,
                scheduledAt: reminder.scheduledAt
            )
        } catch {
            print("❌ Notification schedule failed:", error)
            // Keep the reminder even if scheduling fails.
        }

        return reminder
    }
}
