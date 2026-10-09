//
//  MoreIntents.swift
//  WithYou
//
//  Siri / Shortcuts entry points that open the app somewhere specific.
//  Each one hands a route to `AppRouter`; `RootView` and `TodayView` take it from there.
//

import Foundation
import AppIntents
import SwiftData

// MARK: - Start Focus

struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus"
    static var description = IntentDescription("Open WithYou to start a focus session, optionally on something specific.")

    @Parameter(title: "What do you want to focus on?")
    var focusTitle: String?

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let trimmed = focusTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !trimmed.isEmpty {
            let context = AppModelContainer.shared.mainContext
            ProfileStore.ensureDefaultProfile(in: context)
            let profile = ProfileStore.activeProfile(in: context)

            // Asking twice for the same thing keeps the session that's already there.
            let alreadyFocusing = FocusSessionStore.activeSession(in: context)?.focusTitle == trimmed
            if !alreadyFocusing {
                let profileMinutes = profile?.defaultFocusMinutes ?? 25
                let minutes = profileMinutes > 0 ? profileMinutes : 25
                let startStep = CaptureParser().parse(trimmed, profile: profile).startStep

                // Not begun yet: the Focus tab opens on Brain Dump, then "Begin Focus".
                try FocusSessionStore.start(
                    title: trimmed,
                    startStep: startStep,
                    durationSeconds: minutes * 60,
                    beginImmediately: false,
                    in: context
                )
            }
        }

        AppRouter.shared.open(.focus)
        return .result()
    }
}

// MARK: - Refocus

struct RefocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Refocus"
    static var description = IntentDescription("Open a 30-second breathing reset.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.refocus)
        return .result()
    }
}

// MARK: - Voice capture

/// Opens WithYou listening, so the person can say what's on their mind and review it
/// before anything is saved. Good on the Action Button.
struct VoiceCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Voice capture"
    static var description = IntentDescription("Open WithYou listening, so you can say what’s on your mind and look it over before saving.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.voiceCapture)
        return .result()
    }
}

// MARK: - I'm stuck

struct ImStuckIntent: AppIntent {
    static var title: LocalizedStringResource = "I’m stuck"
    static var description = IntentDescription("Open WithYou to find a smaller first step.")

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.open(.stuck(reminderId: nil))
        return .result()
    }
}
