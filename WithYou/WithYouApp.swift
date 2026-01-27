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
        

//        Task {
//            print("🔔 Requesting notification authorization…")
//            try? await NotificationManager.shared.requestAuthorization()
//
//            // Print current notification settings
//            let settings = await UNUserNotificationCenter.current().notificationSettings()
//            print("🔧 notification authorizationStatus:", settings.authorizationStatus.rawValue)
//            print("🔧 alertSetting:", settings.alertSetting.rawValue)
//
//            await MainActor.run {
//                print("🔧 isRegisteredForRemoteNotifications BEFORE:", UIApplication.shared.isRegisteredForRemoteNotifications)
//                print("📨 Calling registerForRemoteNotifications()")
//                UIApplication.shared.registerForRemoteNotifications()
//                print("🔧 isRegisteredForRemoteNotifications AFTER:", UIApplication.shared.isRegisteredForRemoteNotifications)
//            }
//        }
        
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

