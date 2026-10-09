//
//  Intents.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import AppIntents
import SwiftData

/// "Capture in WithYou": Siri takes down what the person says and saves it straight away
/// (they asked Siri to save it), then says exactly what it saved.
struct CaptureInWithYouIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture"
    static var description = IntentDescription("Capture a thought, or a few, into your Inbox. Anything with a time is scheduled.")

    @Parameter(title: "What should I capture?")
    var content: String

    static var openAppWhenRun: Bool = false

    /// Siri is waiting, so AI gets this long before the simple rules take over.
    static let aiDeadlineSeconds: Double = 8

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

        // AI may split "call mom and buy milk" into two items, and picks up times.
        // Without AI (or when it's slow) the rules read it as one item, as before.
        let suggestions = await CaptureSaver.suggestions(
            for: content,
            profile: profile,
            within: Self.aiDeadlineSeconds
        )
        let summary = try await CaptureSaver.save(suggestions, source: .siri, in: context)
        let message = CaptureSaver.message(for: summary)
        return .result(dialog: "\(message)")
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
        // Opens straight into voice capture. Can be put on the Action Button in Settings.
        AppShortcut(
            intent: VoiceCaptureIntent(),
            phrases: [
                "Voice capture in \(.applicationName)",
                "Brain dump in \(.applicationName)",
                "Talk it out with \(.applicationName)"
            ],
            shortTitle: "Voice capture",
            systemImageName: "waveform"
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
