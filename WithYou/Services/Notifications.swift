//
//  Notifications.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftData
import UIKit
import UserNotifications
import OSLog

enum ReminderAction: String {
    case started = "REMINDER_STARTED"
    case helpMeStart = "REMINDER_HELP"
    case snooze10 = "REMINDER_SNOOZE_10"
    case reschedTomorrowMorning = "REMINDER_RESCHED_TMORNING"
    case focusWrapUp = "FOCUS_WRAP_UP"
}

enum NotificationCategory {
    static let reminder = "VERBOSE_REMINDER"
    static let focusEnd = "FOCUS_END"
}

/// Owns local notifications: permission, action categories, scheduling, and what
/// happens when someone taps a notification or one of its buttons.
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "notifications")

    private override init() {}

    // MARK: - Setup

    /// Call once at launch (from `AppDelegate`). Registers the action buttons and becomes
    /// the notification delegate. Never shows a permission prompt.
    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.categories)
    }

    /// Asks for permission the first time something is scheduled, then registers for
    /// remote push so the backend gets a token. Safe to call often.
    func ensureAuthorization() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound])
                log.info("Notification permission granted=\(granted, privacy: .public)")
                if granted { await registerForRemoteNotifications() }
            } catch {
                log.error("Notification permission request failed: \(String(describing: error), privacy: .public)")
            }
        case .authorized, .provisional, .ephemeral:
            await registerForRemoteNotifications()
        default:
            break
        }
    }

    /// At launch: refresh the push token only if the person already allowed notifications.
    func registerForRemoteIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await registerForRemoteNotifications()
        default:
            break
        }
    }

    @MainActor
    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    private static var categories: Set<UNNotificationCategory> {
        let started = UNNotificationAction(
            identifier: ReminderAction.started.rawValue,
            title: "I’m starting",
            options: [.foreground]
        )
        let help = UNNotificationAction(
            identifier: ReminderAction.helpMeStart.rawValue,
            title: "Help me start",
            options: [.foreground]
        )
        let snooze = UNNotificationAction(
            identifier: ReminderAction.snooze10.rawValue,
            title: "In 10 minutes",
            options: []
        )
        let tomorrow = UNNotificationAction(
            identifier: ReminderAction.reschedTomorrowMorning.rawValue,
            title: "Tomorrow morning",
            options: []
        )
        let reminder = UNNotificationCategory(
            identifier: NotificationCategory.reminder,
            actions: [started, help, snooze, tomorrow],
            intentIdentifiers: [],
            options: []
        )

        let wrapUp = UNNotificationAction(
            identifier: ReminderAction.focusWrapUp.rawValue,
            title: "Wrap up",
            options: [.foreground]
        )
        let focus = UNNotificationCategory(
            identifier: NotificationCategory.focusEnd,
            actions: [wrapUp],
            intentIdentifiers: [],
            options: []
        )

        return [reminder, focus]
    }

    // MARK: - Scheduling

    func scheduleReminder(id: UUID, title: String, body: String, scheduledAt: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.reminder
        content.userInfo = ["reminderId": id.uuidString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(req)
    }

    func scheduleFocusEnd(sessionId: UUID, focusTitle: String, endDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Focus time is up"
        content.body = "That counted. Wrap up “\(focusTitle)” whenever you’re ready."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.focusEnd
        content.userInfo = ["focusSessionId": sessionId.uuidString]

        let interval = max(1, endDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)

        let req = UNNotificationRequest(identifier: focusEndNotificationId(sessionId: sessionId), content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(req)
    }

    func cancelFocusEnd(sessionId: UUID) {
        let id = focusEndNotificationId(sessionId: sessionId)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func cancelReminder(id: UUID) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    private func focusEndNotificationId(sessionId: UUID) -> String {
        "focus_end_\(sessionId.uuidString)"
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show notifications even while the app is open (quietly, as a banner).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        let actionId = response.actionIdentifier

        if let idStr = userInfo["reminderId"] as? String,
           let reminderId = UUID(uuidString: idStr) {
            await handleReminderResponse(actionId: actionId, reminderId: reminderId)
            return
        }

        if userInfo["focusSessionId"] != nil {
            await MainActor.run { AppRouter.shared.open(.focus) }
            return
        }

        // Backend pushes carry a deep link such as "withyou://today".
        if let link = userInfo["deep_link"] as? String {
            await MainActor.run { AppRouter.shared.open(deepLink: link) }
        }
    }

    @MainActor
    private func handleReminderResponse(actionId: String, reminderId: UUID) async {
        let context = AppModelContainer.shared.mainContext
        let descriptor = FetchDescriptor<VerboseReminder>(
            predicate: #Predicate<VerboseReminder> { $0.id == reminderId }
        )

        guard let reminder = (try? context.fetch(descriptor))?.first else {
            // The reminder was let go or completed in the meantime. Just open the app calmly.
            AppRouter.shared.open(.today)
            return
        }

        switch ReminderAction(rawValue: actionId) {
        case .snooze10:
            let later = Date().addingTimeInterval(10 * 60)
            do {
                try ReminderStore.reschedule(reminder, to: later, in: context)
            } catch {
                log.error("Snooze failed: \(String(describing: error), privacy: .public)")
            }

        case .reschedTomorrowMorning:
            let profile = ProfileStore.activeProfile(in: context)
            do {
                try ReminderStore.reschedule(reminder, to: ReminderStore.nextMorning(profile: profile), in: context)
            } catch {
                log.error("Reschedule failed: \(String(describing: error), privacy: .public)")
            }

        case .started:
            reminder.isStarted = true
            try? context.save()
            AppRouter.shared.open(.startFocus(reminderId: reminderId))

        case .helpMeStart:
            AppRouter.shared.open(.stuck(reminderId: reminderId))

        default:
            // Plain tap on the notification.
            AppRouter.shared.open(.reminder(reminderId))
        }
    }
}
