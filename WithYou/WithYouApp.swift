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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        // The same container the App Intents and notification actions use,
        // so every entry point sees the same data.
        .modelContainer(AppModelContainer.shared)
    }
}
