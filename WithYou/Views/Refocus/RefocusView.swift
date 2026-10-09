//
//  RefocusView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

struct RefocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hapticBreathing") private var hapticBreathing: Bool = true
    @AppStorage("refocusPattern") private var pattern: BreathPattern = .calm

    @State private var mantra: String = ""
    /// The one clock for a session: the orb, the words and the haptics all read it.
    /// Replaced whenever a session starts (on open, "Again" and a new pattern).
    @State private var engine = BreathEngine(pattern: .calm, startDate: Date())
    /// Drives the orb's slow change of shape. Never restarts, so the shape never jumps.
    @State private var motionClock = BreathClock(startDate: Date())
    /// Eases the orb over when a new pattern starts mid-breath.
    @State private var handoff: BreathLevelHandoff?
    @State private var haptics = BreathHaptics()
    @State private var phrase: String = BreathWords.word(for: .inhale, occurrence: 0)
    @State private var hasStarted = false
    @State private var isFinished = false
    /// The last phase whose words, haptic and announcement have already run.
    @State private var handledPhaseIndex = -1
    /// Bumped by "Again" so the words don't repeat the previous run.
    @State private var runCount = 0
    /// True while Refocus is what keeps the screen on (Focus may already be doing it).
    @State private var isKeepingScreenOn = false

    init() {}

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                TimelineView(schedule) { timeline in
                    AmbientBreathBackground(level: displayedLevel(at: timeline.date))
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)

                ScrollView {
                    VStack(spacing: 16) {
                        header

                        TimelineView(schedule) { timeline in
                            breathing(at: timeline.date)
                        }

                        patternMenu

                        buttons
                            .padding(.top, 4)
                    }
                    .padding()
                }
            }
            .navigationTitle("Refocus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .tint(.appAccent)
            .onAppear {
                loadMantra()
                if !hasStarted { start() }
            }
            .onDisappear {
                haptics.stop()
                keepScreenOn(false)
            }
            // Pauses in the background and picks up exactly where it left off.
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: pause()
                case .active: resume()
                default: break
                }
            }
            .onChange(of: pattern) {
                start()
            }
            .onChange(of: hapticBreathing) { _, isOn in
                if !isOn { haptics.stop() }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(spacing: 8) {
            Text("Refocus")
                .font(.title).bold()
                .foregroundStyle(.appPrimaryText)
                .accessibilityAddTraits(.isHeader)

            if !mantra.isEmpty {
                Text(mantra)
                    .font(.title3)
                    .foregroundStyle(.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    /// The orb and the words for one moment of the breath.
    private func breathing(at date: Date) -> some View {
        let state = engine.state(at: date)
        let secondsLeft = max(1, Int(state.remainingSeconds.rounded(.up)))

        return VStack(spacing: 16) {
            BreathOrbView(level: displayedLevel(at: date), time: motionClock.elapsed(at: date))
                .padding(.vertical, 6)

            breathCard(secondsLeft: secondsLeft)
        }
        // Words, haptics and VoiceOver follow phase changes, not frames.
        .onChange(of: state.phaseIndex) {
            handlePhase(engine.state(at: Date()))
        }
    }

    private func breathCard(secondsLeft: Int) -> some View {
        VStack(spacing: 8) {
            if isFinished {
                Text("Nice. Ready when you are.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.appPrimaryText)
                    .transition(.opacity)
            } else {
                Text(phrase)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .foregroundStyle(.appPrimaryText)
                    .id(phrase)
                    .transition(.opacity)

                Text(secondsText(secondsLeft))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.appSecondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .cardStyle(padding: 16, cornerRadius: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Refocus breathing")
        .accessibilityValue(breathAccessibilityValue(secondsLeft: secondsLeft))
    }

    private func breathAccessibilityValue(secondsLeft: Int) -> String {
        if isFinished { return "Finished. Ready when you are." }
        return "\(phrase). \(secondsText(secondsLeft)) left."
    }

    private func secondsText(_ seconds: Int) -> String {
        seconds == 1 ? "1 second" : "\(seconds) seconds"
    }

    private var patternMenu: some View {
        Menu {
            Picker("Breathing pattern", selection: $pattern) {
                ForEach(BreathPattern.allCases) { option in
                    Text(option.menuTitle)
                        .tag(option)
                }
            }
        } label: {
            Label(pattern.menuTitle, systemImage: "wind")
                .font(.subheadline)
                .foregroundStyle(.appSecondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Breathing pattern")
        .accessibilityValue(pattern.menuTitle)
        .accessibilityHint("Starts again with the rhythm you choose")
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.appAccent)

            if isFinished {
                Button {
                    Haptics.tap()
                    runCount += 1
                    start()
                } label: {
                    Label("Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.appAccent)
                .accessibilityHint("Another minute of slow breathing")
            }
        }
    }

    // MARK: - Breathing

    /// Runs every frame while breathing; stops while paused, finished or not yet started.
    private var schedule: AnimationTimelineSchedule {
        .animation(minimumInterval: nil, paused: !hasStarted || isFinished || engine.isPaused)
    }

    /// How full the orb looks: the breath itself, eased over after a pattern change.
    private func displayedLevel(at date: Date) -> Double {
        let level = engine.state(at: date).level
        guard let handoff else { return level }
        return handoff.level(toward: level, at: date)
    }

    private func loadMantra() {
        guard mantra.isEmpty else { return }
        let profile = ProfileStore.activeProfile(in: context)
        let saved = profile?.defaultMantra.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mantra = saved.isEmpty ? "I am here now." : saved
    }

    /// Starts a fresh session with the chosen pattern: on open, on "Again" and on a new pattern.
    private func start() {
        let now = Date()
        // A new pattern mid-breath eases the orb over instead of snapping it back.
        if hasStarted, !isFinished {
            handoff = BreathLevelHandoff(fromLevel: displayedLevel(at: now), startDate: now)
        } else {
            handoff = nil
        }
        engine = BreathEngine(pattern: pattern, startDate: now)
        motionClock.resume(at: now)
        // A minute of stillness shouldn't let the screen lock mid-breath.
        keepScreenOn(true)
        hasStarted = true
        handledPhaseIndex = -1
        withAnimation(.easeInOut(duration: 0.4)) {
            isFinished = false
        }
        handlePhase(engine.state(at: now))
    }

    /// Runs once per phase: new words, that phase's haptic and a VoiceOver announcement.
    private func handlePhase(_ state: BreathState) {
        // A stale frame can briefly report an earlier phase; only ever move forward.
        guard state.phaseIndex > handledPhaseIndex else { return }
        handledPhaseIndex = state.phaseIndex

        if let current = handoff, current.isComplete(at: Date()) {
            handoff = nil
        }

        if state.isFinished {
            finish()
            return
        }

        // Rotating by occurrence (and by run, for "Again") never repeats the previous phrase.
        let next = BreathWords.word(for: state.phase.kind, occurrence: state.occurrence + runCount)
        withAnimation(.easeInOut(duration: 0.6)) {
            phrase = next
        }

        if hapticBreathing, !engine.isPaused {
            haptics.play(BreathHapticCurve(state: state))
        }
        AccessibilityNotification.Announcement(next).post()
    }

    private func finish() {
        haptics.stop()
        motionClock.pause(at: Date())
        handoff = nil
        keepScreenOn(false)

        // No abrupt dismissal: rest here until the person chooses Done or Again.
        withAnimation(.easeInOut(duration: 0.6)) {
            isFinished = true
        }
        if hapticBreathing { Haptics.tap() }
        let message: String = "Nice. Ready when you are."
        AccessibilityNotification.Announcement(message).post()
    }

    private func pause() {
        guard hasStarted else { return }
        let now = Date()
        engine.pause(at: now)
        motionClock.pause(at: now)
        haptics.stop()
    }

    private func resume() {
        guard hasStarted, engine.isPaused else { return }
        let now = Date()
        engine.resume(at: now)
        guard !isFinished else { return }
        motionClock.resume(at: now)

        let state = engine.state(at: now)
        if hapticBreathing, !state.isFinished {
            // Pick the vibration up mid-phase, where the breath left off.
            haptics.play(BreathHapticCurve(state: state), tapIfUnavailable: false)
        }
    }

    /// Keeps the screen from locking during a session, without undoing Focus's own setting.
    private func keepScreenOn(_ on: Bool) {
        if on {
            guard !UIApplication.shared.isIdleTimerDisabled else { return }
            UIApplication.shared.isIdleTimerDisabled = true
            isKeepingScreenOn = true
        } else if isKeepingScreenOn {
            UIApplication.shared.isIdleTimerDisabled = false
            isKeepingScreenOn = false
        }
    }
}
