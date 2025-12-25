//
//  Intents.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import AppIntents
import SwiftData

struct CaptureInWithYouIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture"
    static var description = IntentDescription("Capture a thought into Inbox or schedule if a time is detected.")

    @Parameter(title: "What should I capture?")
    var content: String

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let container = try ModelContainer(
            for: InboxItem.self, VerboseReminder.self,
                FocusSession.self, FocusDumpItem.self,
                UserProfile.self, AppState.self
        )
        let context = ModelContext(container)

        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        // If focusing, route to Focus Dump (if enabled)
        if let active = FocusStore.activeSession(in: context),
           (profile?.routeSiriToFocusDumpWhenActive ?? true) {
            context.insert(FocusDumpItem(text: content, sessionId: active.id))
            try context.save()
            return .result(dialog: "Captured. Keep focusing.")
        }

        let parser = CaptureParser()
        let parsed = parser.parse(content, profile: profile)

        if let when = parsed.scheduledAt {
            let reminder = VerboseReminder(
                title: parsed.title,
                startStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes,
                scheduledAt: when
            )
            context.insert(reminder)
            try context.save()

            let body = "Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)\nTap “Help me start” if you’re stuck."
            try await NotificationManager.shared.scheduleReminder(id: reminder.id, title: reminder.title, body: body, scheduledAt: reminder.scheduledAt)

            return .result(dialog: "Scheduled for \(when.formatted(date: .abbreviated, time: .shortened)).")
        } else {
            let inbox = InboxItem(
                content: content,
                title: parsed.title,
                source: .siri,
                startStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes
            )
            context.insert(inbox)
            try context.save()
            return .result(dialog: "Saved to Inbox.")
        }
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
    }

    static var shortcutTileColor: ShortcutTileColor = .blue
}

