//
//  AppDelegate.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/20/26.
//

import UIKit
import OSLog

/// Launch-time setup for notifications and push.
///
/// - `NotificationManager` is the notification delegate (taps, actions, foreground banners).
/// - Permission is never requested at launch. `NotificationManager.ensureAuthorization()`
///   asks the first time something is scheduled.
/// - If the person already allowed notifications, we refresh the APNs token on every
///   launch, in every build configuration (the old debug-only path meant release and
///   TestFlight builds never registered).
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "push")
    private var didBecomeActiveObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.configure()

        Task {
            await NotificationManager.shared.registerForRemoteIfAuthorized()
        }

        // Keep the backend in sync when timezone or permission changes while we were away.
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if let token = DeviceRegistration.cachedToken() {
                    await DeviceRegistration.registerIfNeeded(token: token)
                }
            }
        }

        return true
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        log.error("Failed to register for remote notifications: \(String(describing: error), privacy: .public)")
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        log.info("Received APNs token: \(token, privacy: .private)")

        DeviceRegistration.storeToken(token)
        Task { @MainActor in
            await DeviceRegistration.registerIfNeeded(token: token)
        }
    }
}
