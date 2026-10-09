//
//  AppDelegate.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/20/26.
//

import Foundation
import UIKit

/// Launch-time setup for local notifications.
///
/// - `NotificationManager` is the notification delegate (taps, actions, foreground banners).
/// - Permission is never requested at launch. `NotificationManager.ensureAuthorization()`
///   asks the first time something is scheduled, or when the daily check-in is turned on.
/// - The app no longer registers for remote (push) notifications; everything is local.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationManager.shared.configure()
        LegacyServerCleanup.runIfNeeded()
        // Also refreshed whenever the app becomes active (see WithYouApp).
        DailyCheckIn.reschedule()
        return true
    }
}

/// Removes, once, what the retired push server left on this iPhone: the cached push token,
/// registration bookkeeping, the old sharing choice, the install ID and its Keychain secret.
/// Nothing is sent anywhere; the server itself has been shut down.
enum LegacyServerCleanup {
    static let doneKey = "withyou.legacy_server_cleanup_done"
    static let installIdKey = "withyou.install_id"

    /// UserDefaults keys the old `DeviceRegistration` and `InstallID` used.
    static let legacyKeys = [
        "withyou.apns_token",
        "withyou.apns_last_sent_signature",
        "withyou.apns_last_failure_signature",
        "withyou.apns_last_failure_at",
        "withyou.server_sharing_enabled",
        installIdKey
    ]

    /// - Parameter deleteKeychainItem: removes a Keychain item by account and returns true
    ///   when it is gone. If it fails (for example before the first unlock), nothing else is
    ///   removed and the cleanup runs again at the next launch.
    static func runIfNeeded(
        defaults: UserDefaults = .standard,
        deleteKeychainItem: (String) -> Bool = { KeychainStore.delete(account: $0) }
    ) {
        guard !defaults.bool(forKey: doneKey) else { return }

        if let installId = defaults.string(forKey: installIdKey), !installId.isEmpty {
            guard deleteKeychainItem(KeychainStore.installSecretAccount(for: installId)) else { return }
        }
        for key in legacyKeys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: doneKey)
    }
}
