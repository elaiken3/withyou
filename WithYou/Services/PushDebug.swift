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
#if DEBUG
        print("🚀 PushDebug.register() started (print)")
        log.info("🚀 PushDebug.register() started")

        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            print("🔔 requestAuthorization granted=\(granted) (print)")
            log.info("🔔 requestAuthorization granted=\(granted)")
        } catch {
            print("❌ requestAuthorization error=\(error) (print)")
            log.error("❌ requestAuthorization error=\(String(describing: error))")
        }

        let settings = await center.notificationSettings()
        print("🔧 authorizationStatus=\(settings.authorizationStatus.rawValue) (print)")
        log.info("🔧 authorizationStatus=\(settings.authorizationStatus.rawValue)")

        print("📨 calling registerForRemoteNotifications() (print)")
        log.info("📨 calling UIApplication.registerForRemoteNotifications()")

        UIApplication.shared.registerForRemoteNotifications()

        print("📨 called registerForRemoteNotifications() (print)")
        log.info("📨 called UIApplication.registerForRemoteNotifications()")
#endif
    }
}
