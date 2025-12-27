//
//  Notifications.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import UserNotifications

enum ReminderAction: String {
    case started = "REMINDER_STARTED"
    case helpMeStart = "REMINDER_HELP"
    case snooze10 = "REMINDER_SNOOZE_10"
    case reschedTomorrowMorning = "REMINDER_RESCHED_TMORNING"
    case focusWrapUp = "FOCUS_WRAP_UP"
}

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() {}

    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])

        let started = UNNotificationAction(identifier: ReminderAction.started.rawValue, title: "Started", options: [.foreground])
        let help = UNNotificationAction(identifier: ReminderAction.helpMeStart.rawValue, title: "Help me start", options: [.foreground])
        let snooze = UNNotificationAction(identifier: ReminderAction.snooze10.rawValue, title: "Snooze 10 min", options: [])
        let resched = UNNotificationAction(identifier: ReminderAction.reschedTomorrowMorning.rawValue, title: "Tomorrow morning", options: [])

        let category = UNNotificationCategory(
            identifier: "VERBOSE_REMINDER",
            actions: [started, help, snooze, resched],
            intentIdentifiers: [],
            options: []
        )
        
        let wrapUp = UNNotificationAction(
            identifier: ReminderAction.focusWrapUp.rawValue,
            title: "Wrap up",
            options: [.foreground]
        )

        let focusCategory = UNNotificationCategory(
            identifier: "FOCUS_END",
            actions: [wrapUp],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([category, focusCategory])
    }

    func scheduleReminder(id: UUID, title: String, body: String, scheduledAt: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = "VERBOSE_REMINDER"
        content.userInfo = ["reminderId": id.uuidString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: scheduledAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id.uuidString, content: content, trigger: trigger)

        try await UNUserNotificationCenter.current().add(req)
    }
    
    func scheduleFocusEnd(sessionId: UUID, focusTitle: String, endDate: Date) async throws {
        let content = UNMutableNotificationContent()
        content.title = "Focus complete"
        content.body = "Nice work on “\(focusTitle)”. Want to wrap up?"
        content.sound = .default
        content.categoryIdentifier = "FOCUS_END"
        content.userInfo = ["focusSessionId": sessionId.uuidString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: endDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let req = UNNotificationRequest(identifier: focusEndNotificationId(sessionId: sessionId), content: content, trigger: trigger)
        try await UNUserNotificationCenter.current().add(req)
    }

    func cancelFocusEnd(sessionId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [focusEndNotificationId(sessionId: sessionId)])
    }

    private func focusEndNotificationId(sessionId: UUID) -> String {
        "focus_end_\(sessionId.uuidString)"
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {

        let userInfo = response.notification.request.content.userInfo

        // Reminder
        if let idStr = userInfo["reminderId"] as? String,
           let uuid = UUID(uuidString: idStr) {
            NotificationCenter.default.post(
                name: .reminderActionReceived,
                object: nil,
                userInfo: ["reminderId": uuid, "actionId": response.actionIdentifier]
            )
            return
        }

        // Focus end
        if let sIdStr = userInfo["focusSessionId"] as? String,
           let sId = UUID(uuidString: sIdStr) {
            NotificationCenter.default.post(
                name: .focusActionReceived,
                object: nil,
                userInfo: ["sessionId": sId, "actionId": response.actionIdentifier]
            )
        }
    }
}

extension Notification.Name {
    static let reminderActionReceived = Notification.Name("reminderActionReceived")
    static let focusActionReceived = Notification.Name("focusActionReceived")   // NEW
}


