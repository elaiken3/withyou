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

    @State private var secondsRemaining: Int = 32   // 4/4 cycles fit nicely into 32s
    @State private var timer: Timer?

    @State private var isInhaling: Bool = true

    private let cycleSeconds = 8
    private let inhaleSeconds = 4
    private let exhaleSeconds = 4

    private var mantra: String {
        ProfileStore.activeProfile(in: context)?.defaultMantra ?? "I am here now."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                AmbientBreathBackground(isInhaling: isInhaling)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 16) {
                    VStack(spacing: 8) {
                        Text("Refocus")
                            .font(.title).bold()
                            .foregroundStyle(.appPrimaryText)

                        Text(mantra)
                            .font(.title3)
                            .foregroundStyle(.appSecondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    BreathingOrb(isInhaling: isInhaling)
                        .padding(.vertical, 6)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("\(secondsRemaining)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(.appPrimaryText)

                        Text(breathPrompt(for: secondsRemaining))
                                .font(.title3)
                                .foregroundStyle(.appSecondaryText)
                                .transition(.opacity)
                                .animation(.easeInOut(duration: 0.4), value: isInhaling)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Refocus countdown")
                    .accessibilityValue("\(secondsRemaining) seconds, \(breathPrompt(for: secondsRemaining))")
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.appSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(.appHairline.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)

                    Button("Done") {
                        Haptics.tap()
                        stop()
                        Haptics.success()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Refocus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        stop()
                        dismiss()
                    }
                }
            }
            .tint(.appAccent)
            .onAppear { start() }
            .onDisappear { stop() }
        }
    }

    private func start() {
        stop()

        // Pick a default that matches full cycles (optional)
        secondsRemaining = 32

        // Align inhale/exhale with the cycle:
        // phase 0...3 => inhale, phase 4...7 => exhale
        isInhaling = (secondsRemaining % cycleSeconds) < inhaleSeconds

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 {
                secondsRemaining -= 1

                let phase = secondsRemaining % cycleSeconds
                let nextIsInhaling = phase < inhaleSeconds

                if nextIsInhaling != isInhaling {
                    // tiny organic lag
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isInhaling = nextIsInhaling
                    }
                }
            } else {
                stop()
                Haptics.success()
                dismiss()
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func breathPrompt(for seconds: Int) -> String {
        let phase = seconds % cycleSeconds
        return phase < inhaleSeconds
            ? "In… 1 2 3 4"
            : "Out… 1 2 3 4"
    }
    
    private func countdownString(from n: Int) -> String {
        // Returns "1 2 3 4" style, but truncated to n.
        // If you prefer "In… 1 2 3 4" always, tell me and I’ll adjust.
        if n <= 1 { return "1" }
        if n == 2 { return "1 2" }
        if n == 3 { return "1 2 3" }
        return "1 2 3 4"
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

struct BreathingOrb: View {
    let isInhaling: Bool

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
                .scaleEffect(isInhaling ? 1.14 : 0.95)
                .opacity(isInhaling ? 1.0 : 0.82)
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
                .scaleEffect(isInhaling ? 1.0 : 0.78)
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
                .offset(x: isInhaling ? -18 : -10, y: isInhaling ? -26 : -18)
                .blur(radius: 2)
                .blendMode(.screen)
                .animation(.easeInOut(duration: 4.0), value: isInhaling)
        }
        .frame(width: 230, height: 230)
        .accessibilityHidden(true)
    }
}
