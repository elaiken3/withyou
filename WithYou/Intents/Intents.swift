//
//  Intents.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import AppIntents
import SwiftData

struct CaptureInWithYouIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture"
    static var description = IntentDescription("Capture a thought into Inbox, or schedule it if a time is mentioned.")

    @Parameter(title: "What should I capture?")
    var content: String

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Always the app's one container: opening the store with a subset of models
        // could migrate it and drop data.
        let context = AppModelContainer.shared.mainContext

        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        // While focusing, park the thought in the session's brain dump (if enabled).
        if let active = FocusSessionStore.activeSession(in: context),
           profile?.routeSiriToFocusDumpWhenActive ?? true {
            context.insert(FocusDumpItem(text: content, sessionId: active.id))
            try context.save()
            return .result(dialog: "Parked. Keep focusing.")
        }

        let parser = CaptureParser()
        let parsed = parser.parse(content, profile: profile)

        if let when = parsed.scheduledAt {
            _ = try await ReminderStore.createAndSchedule(
                title: parsed.title,
                startStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes,
                scheduledAt: when,
                in: context
            )
            return .result(dialog: "Scheduled for \(when.friendlyDayTime).")
        }

        let inbox = InboxItem(
            content: content,
            title: parsed.title,
            source: .siri,
            startStep: parsed.startStep,
            estimateMinutes: parsed.estimateMinutes
        )
        context.insert(inbox)
        try context.save()
        return .result(dialog: "Saved. It’s in your Inbox.")
    }
}

struct WithYouShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureInWithYouIntent(),
            phrases: [
                "Capture in \(.applicationName)",
                "Quick capture with \(.applicationName)",
                "Remember in \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: [
                "Start focus in \(.applicationName)",
                "Start a focus session in \(.applicationName)",
                "Help me focus with \(.applicationName)"
            ],
            shortTitle: "Start Focus",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: RefocusIntent(),
            phrases: [
                "Refocus with \(.applicationName)",
                "Take a breath with \(.applicationName)"
            ],
            shortTitle: "Refocus",
            systemImageName: "wind"
        )
        AppShortcut(
            intent: ImStuckIntent(),
            phrases: [
                "I'm stuck in \(.applicationName)",
                "Help me start with \(.applicationName)"
            ],
            shortTitle: "I’m stuck",
            systemImageName: "hand.raised"
        )
    }

    // Closest tile to the app's muted slate accent.
    static var shortcutTileColor: ShortcutTileColor = .grayBlue
}
