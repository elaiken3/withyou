//
//  WithYouApp.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

@main
struct WithYouApp: App {
    let container: ModelContainer

    init() {
        container = try! ModelContainer(
            for: InboxItem.self,
                VerboseReminder.self,
                FocusSession.self,
                FocusDumpItem.self,
                FocusBlock.self,
                UserProfile.self,
                AppState.self
        )

        Task {
            try? await NotificationManager.shared.requestAuthorization()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}

