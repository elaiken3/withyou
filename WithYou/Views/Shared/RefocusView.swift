//
//  RefocusView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct RefocusView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage("hapticBreathing") private var hapticBreathing: Bool = true

    /// Four slow breaths: 4 seconds in, 4 seconds out.
    private static let totalSeconds = 32
    private static let phaseSeconds = 4

    private static let inhalePhrases = ["Breathe in", "In, slowly", "Fill up gently", "Let the air in"]
    private static let exhalePhrases = ["Breathe out", "Let it go", "Slowly out", "Soften your shoulders"]

    @State private var mantra: String = ""
    @State private var secondsRemaining: Int = RefocusView.totalSeconds
    @State private var isInhaling: Bool = true
    @State private var phrase: String = RefocusView.inhalePhrases[0]
    @State private var isFinished = false
    /// Bumped by "Again" to restart the breathing task.
    @State private var runCount = 0

    init() {}

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                AmbientBreathBackground(isInhaling: isInhaling)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                ScrollView {
                    VStack(spacing: 16) {
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

                        BreathingOrb(isInhaling: isInhaling)
                            .padding(.vertical, 6)
                            .accessibilityHidden(true)

                        breathCard

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
            .onAppear { loadMantra() }
            // Restarts on "Again"; cancelled automatically when the sheet closes.
            .task(id: runCount) {
                await breathe()
            }
        }
    }

    // MARK: - Pieces

    private var breathCard: some View {
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

                Text("\(secondsRemaining) seconds")
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
        .accessibilityValue(breathAccessibilityValue)
    }

    private var breathAccessibilityValue: String {
        if isFinished { return "Finished. Ready when you are." }
        return "\(phrase). \(secondsRemaining) seconds left."
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
                } label: {
                    Label("Again", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.appAccent)
                .accessibilityHint("Another 30 seconds of breathing")
            }
        }
    }

    // MARK: - Breathing

    private func loadMantra() {
        guard mantra.isEmpty else { return }
        let profile = ProfileStore.activeProfile(in: context)
        let saved = profile?.defaultMantra.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        mantra = saved.isEmpty ? "I am here now." : saved
    }

    private func breathe() async {
        withAnimation(.easeInOut(duration: 0.4)) {
            isFinished = false
        }
        secondsRemaining = Self.totalSeconds
        showPhase(0)

        while secondsRemaining > 0 {
            try? await Task.sleep(for: .seconds(1))
            if Task.isCancelled { return }

            secondsRemaining -= 1
            let elapsed = Self.totalSeconds - secondsRemaining
            if secondsRemaining > 0, elapsed % Self.phaseSeconds == 0 {
                showPhase(elapsed / Self.phaseSeconds)
            }
        }

        // No abrupt dismissal: rest here until the person chooses Done or Again.
        withAnimation(.easeInOut(duration: 0.6)) {
            isFinished = true
        }
        if hapticBreathing { Haptics.tap() }
        let message: String = "Nice. Ready when you are."
        AccessibilityNotification.Announcement(message).post()
    }

    /// Phase 0 is the first inhale, 1 the first exhale, and so on.
    private func showPhase(_ index: Int) {
        let inhale = index % 2 == 0
        // Rotating by breath (and by run, for "Again") never repeats the previous phrase.
        let breath = index / 2 + runCount
        let words = inhale ? Self.inhalePhrases : Self.exhalePhrases
        let next = words[breath % words.count]

        withAnimation(.easeInOut(duration: 0.6)) {
            phrase = next
        }
        // The orb and background carry their own slow 4-second animation.
        isInhaling = inhale

        if hapticBreathing { Haptics.tap() }
        AccessibilityNotification.Announcement(next).post()
    }
}

// MARK: - Ambient Background

struct AmbientBreathBackground: View {
    let isInhaling: Bool

    var body: some View {
        ZStack {
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.appAccent.opacity(isInhaling ? 0.20 : 0.10),
                    Color.clear
                ]),
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
            .blur(radius: 18)
            .animation(.easeInOut(duration: 4.0), value: isInhaling)

            RadialGradient(
                gradient: Gradient(colors: [
                    Color.appAccent.opacity(isInhaling ? 0.10 : 0.06),
                    Color.clear
                ]),
                center: .topLeading,
                startRadius: 10,
                endRadius: 380
            )
            .blur(radius: 22)
            .animation(.easeInOut(duration: 4.0), value: isInhaling)
        }
    }
}

// MARK: - Breathing Orb

/// Grows and shrinks with the breath. With Reduce Motion on, it stays the same size
/// and gently brightens and dims instead.
struct BreathingOrb: View {
    let isInhaling: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isInhaling: Bool) {
        self.isInhaling = isInhaling
    }

    private var haloScale: CGFloat {
        reduceMotion ? 1.0 : (isInhaling ? 1.14 : 0.95)
    }

    private var haloOpacity: Double {
        isInhaling ? 1.0 : (reduceMotion ? 0.55 : 0.82)
    }

    private var coreScale: CGFloat {
        reduceMotion ? 0.9 : (isInhaling ? 1.0 : 0.78)
    }

    private var coreOpacity: Double {
        reduceMotion ? (isInhaling ? 1.0 : 0.6) : 1.0
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.appAccent.opacity(0.26),
                            Color.appAccent.opacity(0.02)
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .blur(radius: 16)
                .scaleEffect(haloScale)
                .opacity(haloOpacity)
                .animation(.easeInOut(duration: 4.0), value: isInhaling)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.appAccent.opacity(0.90),
                            Color.appAccent.opacity(0.22)
                        ]),
                        center: .topLeading,
                        startRadius: 12,
                        endRadius: 150
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.appAccent.opacity(0.25), radius: 18, x: 0, y: 10)
                .scaleEffect(coreScale)
                .opacity(coreOpacity)
                .animation(.easeInOut(duration: 4.0), value: isInhaling)

            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color.white.opacity(isInhaling ? 0.22 : 0.14),
                            Color.clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 90
                    )
                )
                .frame(width: 110, height: 110)
                .offset(
                    x: (reduceMotion || isInhaling) ? -18 : -10,
                    y: (reduceMotion || isInhaling) ? -26 : -18
                )
                .blur(radius: 2)
                .blendMode(.screen)
                .animation(.easeInOut(duration: 4.0), value: isInhaling)
        }
        .frame(width: 230, height: 230)
        .accessibilityHidden(true)
    }
}
