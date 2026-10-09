//
//  WithYouApp.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData
import UIKit

@main
struct WithYouApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                // Back from the background: the day, time zone or notification permission
                // may have changed, so the daily check-ins are refreshed.
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        DailyCheckIn.reschedule()
                    }
                }
        }
        // The same container the App Intents and notification actions use,
        // so every entry point sees the same data.
        .modelContainer(AppModelContainer.shared)
    }
}
