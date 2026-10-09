//
//  AppModelContainer.swift
//  WithYou
//

import Foundation
import SwiftData

/// The one SwiftData container for the app and its App Intents.
///
/// Every entry point must open the store with the same model list. Opening it with a
/// subset (as the Siri intent used to) asks SwiftData to migrate the store to a
/// different schema, which can drop data for the missing models.
enum AppModelContainer {
    static let shared: ModelContainer = {
        // SwiftData keeps the store in Application Support, which doesn't exist on a fresh
        // install. Creating it first avoids a burst of CoreData errors on first launch.
        try? FileManager.default.createDirectory(
            at: URL.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        do {
            return try ModelContainer(
                for: InboxItem.self,
                    VerboseReminder.self,
                    FocusSession.self,
                    FocusDumpItem.self,
                    FocusBlock.self,
                    FocusDurationPreset.self,
                    UserProfile.self,
                    AppState.self
            )
        } catch {
            fatalError("Could not open the WithYou data store: \(error)")
        }
    }()
}
