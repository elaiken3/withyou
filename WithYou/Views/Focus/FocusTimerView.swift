//
//  FocusTimerView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct FocusTimerView: View {
    @Environment(\.modelContext) private var context
    let session: FocusSession
    var onFinish: () -> Void

    @State private var secondsRemaining: Int = 0
    @State private var isPaused: Bool = false
    @State private var showAddThought = false
    @State private var thoughtText = ""
    @State private var showRefocus = false
    @State private var timer: Timer?
    @State private var startedAt: Date?
    @State private var totalPausedSeconds: Int = 0
    @State private var pausedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(format(secondsRemaining))
                .font(.system(size: 56, weight: .bold, design: .rounded))

            Text("Only this matters right now.")
                .foregroundStyle(.secondary)

            Text(session.focusTitle).font(.title2).bold()

            if !session.focusStartStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Start: \(session.focusStartStep)")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(isPaused ? "Resume" : "Pause") {
                    togglePause()
                }
                .buttonStyle(.bordered)

                Button("Refocus") { showRefocus = true }
                    .buttonStyle(.bordered)

                Button("Add thought") { showAddThought = true }
                    .buttonStyle(.bordered)

                Button("End") { endSession() }
                    .buttonStyle(.borderedProminent)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            ensureStartedAt()
            recalcRemaining()
            startTimer()
        }
        .onDisappear { timer?.invalidate() }
        .sheet(isPresented: $showAddThought) { addThoughtSheet }
        .sheet(isPresented: $showRefocus) { RefocusView() }
    }

    private var addThoughtSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Park a thought").font(.title2).bold()
                TextField("Type or dictate…", text: $thoughtText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)

                Button("Save") {
                    let trimmed = thoughtText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        context.insert(FocusDumpItem(text: trimmed, sessionId: session.id))
                        try? context.save()
                    }
                    thoughtText = ""
                    showAddThought = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(thoughtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("Add thought")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { showAddThought = false } } }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            // If paused, keep the display steady
            if isPaused { return }

            recalcRemaining()

            if secondsRemaining <= 0 {
                endSession()
            }
        }
    }

    private func endSession() {
        timer?.invalidate()
        session.isActive = false
        session.endedAt = Date()
        try? context.save()
        onFinish()
    }

    private func format(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
    
    private func ensureStartedAt() {
        if session.startedAt == nil {
            session.startedAt = Date()
            try? context.save()
        }
        startedAt = session.startedAt
    }

    private func togglePause() {
        if isPaused {
            // resuming
            if let pausedAt {
                totalPausedSeconds += Int(Date().timeIntervalSince(pausedAt))
            }
            self.pausedAt = nil
            isPaused = false
        } else {
            // pausing
            pausedAt = Date()
            isPaused = true
        }
        recalcRemaining()
    }

    private func recalcRemaining() {
        guard let startedAt else {
            secondsRemaining = session.durationSeconds
            return
        }

        let elapsed = Int(Date().timeIntervalSince(startedAt))
        let effectiveElapsed = max(0, elapsed - totalPausedSeconds)
        secondsRemaining = max(0, session.durationSeconds - effectiveElapsed)
    }

}
