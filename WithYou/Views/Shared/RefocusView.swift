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
        VStack(spacing: 16) {
            Text("Refocus").font(.title).bold()
            Text(mantra)
                .font(.title2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("\(secondsRemaining)")
                .font(.system(size: 56, weight: .bold, design: .rounded))

            Text(breathPrompt(for: secondsRemaining))
                .font(.title3)
                .foregroundStyle(.secondary)

            Button("Done") {
                stop()
                dismiss()
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
        .padding()
        .onAppear { start() }
        .onDisappear { stop() }
    }

    private func start() {
        stop()
        secondsRemaining = 30
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
            else { stop(); dismiss() }
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

