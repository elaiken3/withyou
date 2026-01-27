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

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        Task { @MainActor in
            log.info("🔔 Requesting notification authorization…")
            let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            log.info("🔔 Authorization granted: \(granted ?? false, privacy: .public)")

            let settings = await center.notificationSettings()
            log.info("🔧 authorizationStatus: \(settings.authorizationStatus.rawValue, privacy: .public)")

            log.info("📨 Calling registerForRemoteNotifications()…")
            application.registerForRemoteNotifications()
        }

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("✅ APNs token: \(token, privacy: .public)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        log.error("❌ Failed to register for remote notifications: \(String(describing: error), privacy: .public)")
    }

    // Show banners while app is foreground (v1 nice-to-have)
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
