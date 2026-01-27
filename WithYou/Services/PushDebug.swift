//
//  PushDebug.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/21/26.
//

import Foundation
import UIKit
import UserNotifications
import OSLog

@MainActor
enum PushDebug {
    static let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "push")

    static func register() async {
        log.info("🚀 PushDebug.register() started")

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            log.info("🔔 requestAuthorization granted=\(granted)")
        } catch {
            log.error("❌ requestAuthorization error=\(String(describing: error))")
        }

        let settings = await center.notificationSettings()
        log.info("🔧 authorizationStatus=\(settings.authorizationStatus.rawValue)")

        log.info("📨 calling UIApplication.registerForRemoteNotifications()")
        UIApplication.shared.registerForRemoteNotifications()
        log.info("📨 called UIApplication.registerForRemoteNotifications()")
    }
}
