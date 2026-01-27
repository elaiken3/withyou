//
//  AppDelegate.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/20/26.
//

import UIKit
import UserNotifications
import OSLog

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "push")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        log.info("✅ AppDelegate didFinishLaunching")
        UNUserNotificationCenter.current().delegate = self

        Task { @MainActor in
            await PushDebug.register()
            log.info("🔧 isRegisteredForRemoteNotifications (after call): \(application.isRegisteredForRemoteNotifications, privacy: .public)")
        }

        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("✅ APNs token: \(token, privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("❌ Failed to register for remote notifications: \(String(describing: error), privacy: .public)")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
