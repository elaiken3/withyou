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

    // Resume-safe timing
    @State private var startedAt: Date?

    // End-of-timer UX
    @State private var showTimeUpSheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(format(secondsRemaining))
                .font(.system(size: 56, weight: .bold, design: .rounded))

            // Copy polish
            if isPaused {
                Text("Paused. You can resume when you’re ready.")
                    .foregroundStyle(.secondary)
            } else if secondsRemaining == 0 {
                Text("Overtime. Wrap up when you’re ready.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Only this matters right now.")
                    .foregroundStyle(.secondary)
            }

            Text(session.focusTitle)
                .font(.title2)
                .bold()

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
            hydratePauseStateFromSession()
            ensureStartedAt()
            recalcRemaining()
            startTimer()
        }
        .onDisappear { timer?.invalidate() }
        .sheet(isPresented: $showAddThought) { addThoughtSheet }
        .sheet(isPresented: $showRefocus) { RefocusView() }
        .sheet(isPresented: $showTimeUpSheet) { timeUpSheet }
    }

    // MARK: - Sheets

    private var addThoughtSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Park a thought")
                    .font(.title2)
                    .bold()

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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showAddThought = false }
                }
            }
        }
    }

    private var timeUpSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Time’s up.")
                    .font(.title2)
                    .bold()

                Text("That counted. Want to wrap up, extend a little, or keep going?")
                    .foregroundStyle(.secondary)

                Button {
                    extend(byMinutes: 5)
                    showTimeUpSheet = false
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                        Text("Extend 5 minutes")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    // Keep going: dismiss. Session remains active.
                    showTimeUpSheet = false
                } label: {
                    HStack {
                        Image(systemName: "forward")
                        Text("Keep going")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showTimeUpSheet = false
                    endSession()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle")
                        Text("Wrap up")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding()
            .navigationTitle("Session")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { showTimeUpSheet = false }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Timer

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if isPaused { return }

            recalcRemaining()

            if secondsRemaining <= 0 {
                secondsRemaining = 0
                if !showTimeUpSheet {
                    showTimeUpSheet = true
                }
            }
        }
    }

    // MARK: - Session actions

    private func endSession() {
        timer?.invalidate()

        // Clear pause state on end
        session.pausedAt = nil

        session.isActive = false
        session.endedAt = Date()
        try? context.save()

        // This continues to route to Review via FlowView's onFinish handler
        onFinish()
    }

    private func extend(byMinutes minutes: Int) {
        session.durationSeconds += minutes * 60
        try? context.save()
        recalcRemaining()
    }

    // MARK: - Pause persistence + time math

    private func hydratePauseStateFromSession() {
        // session.pausedSeconds persists across restarts
        if let pausedAt = session.pausedAt {
            // If the app was killed while paused, count time since pausedAt too
            let extra = Int(Date().timeIntervalSince(pausedAt))
            if extra > 0 {
                session.pausedSeconds += extra
                session.pausedAt = Date() // keep it paused, but reset anchor
                try? context.save()
            }
            isPaused = true
        } else {
            isPaused = false
        }
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
            // Resume: add elapsed paused time (if any) to pausedSeconds and clear pausedAt
            if let pausedAt = session.pausedAt {
                let delta = Int(Date().timeIntervalSince(pausedAt))
                if delta > 0 { session.pausedSeconds += delta }
            }
            session.pausedAt = nil
            isPaused = false
        } else {
            // Pause: set pausedAt now (persisted)
            session.pausedAt = Date()
            isPaused = true
        }

        try? context.save()
        recalcRemaining()
    }

    private func recalcRemaining() {
        guard let startedAt else {
            secondsRemaining = session.durationSeconds
            return
        }

        let elapsed = Int(Date().timeIntervalSince(startedAt))

        // If currently paused, include time since pausedAt too (so remaining stays stable)
        let livePausedExtra: Int
        if let pausedAt = session.pausedAt {
            livePausedExtra = Int(Date().timeIntervalSince(pausedAt))
        } else {
            livePausedExtra = 0
        }

        let effectiveElapsed = max(0, elapsed - (session.pausedSeconds + max(0, livePausedExtra)))
        secondsRemaining = max(0, session.durationSeconds - effectiveElapsed)
    }

    private func format(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
