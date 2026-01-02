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

    @State private var secondsRemaining: Int = 30
    @State private var timer: Timer?

    private var mantra: String {
        ProfileStore.activeProfile(in: context)?.defaultMantra ?? "I am here now."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

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

                    // Timer card
                    VStack(spacing: 10) {
                        Text("\(secondsRemaining)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundStyle(.appPrimaryText)

                        Text(breathPrompt(for: secondsRemaining))
                            .font(.title3)
                            .foregroundStyle(.appSecondaryText)
                    }
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
        secondsRemaining = 30
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 {
                secondsRemaining -= 1
            } else {
                stop()
                // Small success when it completes naturally
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
        // 6-second cycle: 3 in / 3 out
        let phase = seconds % 6
        return phase >= 3 ? "In… 1 2 3" : "Out… 1 2 3"
    }
}
