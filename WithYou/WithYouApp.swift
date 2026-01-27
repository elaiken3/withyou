//
//  WithYouApp.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData
import UIKit
import UserNotifications

@main
struct WithYouApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    let container: ModelContainer

    init() {
        print("🚀 WithYouApp init")

        container = try! ModelContainer(
            for: InboxItem.self,
                VerboseReminder.self,
                FocusSession.self,
                FocusDumpItem.self,
                FocusBlock.self,
                FocusDurationPreset.self,
                UserProfile.self,
                AppState.self
        )
        
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

