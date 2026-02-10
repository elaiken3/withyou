//
//  FocusTimerView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData
import Combine

struct FocusTimerView: View {
    @Environment(\.modelContext) private var context
    let session: FocusSession
    var onFinish: () -> Void

    @State private var secondsRemaining: Int = 0
    @State private var isPaused: Bool = false
    @State private var showAddThought = false
    @State private var thoughtText = ""
    @State private var showRefocus = false

    @State private var startedAt: Date?
    @State private var showTimeUpSheet: Bool = false
    
    @State private var isEnding = false
    @State private var didEndOnce = false
    @State private var didShowTimeUpSheet = false
    @State private var confirmComplete = false
    
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(format(secondsRemaining))
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .foregroundStyle(.appPrimaryText)

                if isPaused {
                    Text("Paused. You can resume when you’re ready.")
                        .foregroundStyle(.appSecondaryText)
                } else if secondsRemaining == 0 {
                    Text("Overtime. Wrap up when you’re ready.")
                        .foregroundStyle(.appSecondaryText)
                } else {
                    Text("Only this matters right now.")
                        .foregroundStyle(.appSecondaryText)
                }

                // Main focus card
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.focusTitle)
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.appPrimaryText)

                    if !session.focusStartStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Start: \(session.focusStartStep)")
                            .foregroundStyle(.appSecondaryText)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.appSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(.appHairline.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)

                HStack {
                    Button(isPaused ? "Resume" : "Pause") {
                        Haptics.tap()
                        togglePause()
                    }
                    .buttonStyle(.bordered)

                    Button("Refocus") {
                        Haptics.tap()
                        showRefocus = true
                    }
                    .buttonStyle(.bordered)

                    Button("Add thought") {
                        Haptics.tap()
                        showAddThought = true
                    }
                    .buttonStyle(.bordered)

                    Button("End") {
                        Haptics.tap()
                        confirmComplete = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isEnding || didEndOnce)
                }
                .tint(.appAccent)

                Spacer()
            }
            .padding()
        }
        .onAppear {
            hydratePauseStateFromSession()
            ensureStartedAt()
            recalcRemaining()
        }
        .onReceive(tick) { _ in
            guard !isPaused else { return }

            recalcRemaining()

            if secondsRemaining > 0 {
                didShowTimeUpSheet = false
            }

            if secondsRemaining <= 0 {
                secondsRemaining = 0

                // ✅ Only show once per overtime “event”
                if !didShowTimeUpSheet {
                    didShowTimeUpSheet = true
                    showTimeUpSheet = true
                }
            }
        }
        .sheet(isPresented: $showAddThought) {
            addThoughtSheet
                .presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showRefocus) {
            RefocusView()
                .presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showTimeUpSheet) {
            timeUpSheet
                .presentationBackground(Color.appBackground)
        }
        .confirmationDialog(
            "Did you complete “\(session.focusTitle)”?",
            isPresented: $confirmComplete
        ) {
            Button("Yes, completed", role: .none) {
                CompletionStore.completeFromSession(session, in: context)
                onFinish()
            }

            Button("No, just stopping", role: .destructive) {
                endSession()   // ends session but DOES NOT mark complete/remove source
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("If yes, I’ll move it to Completed Today and clear it from your Inbox/Schedule.")
        }
    }

    // MARK: - Sheets

    private var addThoughtSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Park a thought")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.appPrimaryText)

                    CardTextEditor(
                        placeholder: "Type or dictate…",
                        text: $thoughtText,
                        icon: "brain",
                        minHeight: 120
                    )

                    Button("Save") {
                        Haptics.tap()
                        let trimmed = thoughtText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            context.insert(FocusDumpItem(text: trimmed, sessionId: session.id))
                            do {
                                try context.save()
                                Haptics.success()
                            } catch {
                                Haptics.error()
                                print("❌ Save failed (addThought):", error)
                            }
                        }
                        thoughtText = ""
                        showAddThought = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(thoughtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Add thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        showAddThought = false
                    }
                }
            }
            .tint(.appAccent)
        }
    }

    private var timeUpSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 14) {
                    Text("Time’s up.")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.appPrimaryText)

                    Text("That counted. Want to wrap up, extend a little, or keep going?")
                        .foregroundStyle(.appSecondaryText)

                    Button {
                        Haptics.tap()
                        extend(byMinutes: 5)
                        Haptics.success()
                        showTimeUpSheet = false
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Extend 5 minutes")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)

                    Button {
                        Haptics.tap()
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
                        Haptics.tap()
                        showTimeUpSheet = false
                        confirmComplete = true
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
            }
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        showTimeUpSheet = false
                    }
                }
            }
            .tint(.appAccent)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Session actions

    private func endSession() {
        // ✅ Prevent double-end from End button + Wrap up + repeated taps
        guard !isEnding, !didEndOnce else { return }
        isEnding = true
        didEndOnce = true

        // ✅ Close any presented sheets so we don’t loop UI
        showTimeUpSheet = false
        showAddThought = false
        showRefocus = false

        NotificationManager.shared.cancelFocusEnd(sessionId: session.id)

        // ✅ If already ended, don’t rewrite it
        if session.endedAt == nil {
            session.endedAt = Date()
        }
        session.isActive = false

        do {
            try context.save()
            Haptics.success()
            onFinish()
        } catch {
            Haptics.error()
            print("❌ Save failed (endSession):", error)
            didEndOnce = false
            isEnding = false
        }
    }

    private func extend(byMinutes minutes: Int) {
        guard let startedAt else { return }

        // How much time has effectively elapsed (excluding paused time)
        let elapsed = Int(Date().timeIntervalSince(startedAt))

        let livePausedExtra: Int
        if let pausedAt = session.pausedAt {
            livePausedExtra = Int(Date().timeIntervalSince(pausedAt))
        } else {
            livePausedExtra = 0
        }

        let effectiveElapsed = max(0, elapsed - (session.pausedSeconds + max(0, livePausedExtra)))

        // ✅ If user is already overtime, extend from *now*
        // durationSeconds becomes: "time already spent" + "extra minutes"
        session.durationSeconds = effectiveElapsed + (minutes * 60)

        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (extend):", error)
            return
        }

        // ✅ Immediately update UI so timer isn't stuck at 0
        recalcRemaining()
        showTimeUpSheet = false

        Task {
            let endDate = Date().addingTimeInterval(TimeInterval(secondsRemaining))
            NotificationManager.shared.cancelFocusEnd(sessionId: session.id)
            try? await NotificationManager.shared.scheduleFocusEnd(
                sessionId: session.id,
                focusTitle: session.focusTitle,
                endDate: endDate
            )
        }
    }

    // MARK: - Pause persistence + time math

    private func hydratePauseStateFromSession() {
        if let pausedAt = session.pausedAt {
            let extra = Int(Date().timeIntervalSince(pausedAt))
            if extra > 0 {
                session.pausedSeconds += extra
                session.pausedAt = Date()
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
            do {
                try context.save()
            } catch {
                print("❌ Save failed (ensureStartedAt):", error)
            }

            Task {
                let endDate = (session.startedAt ?? Date())
                    .addingTimeInterval(TimeInterval(session.durationSeconds))
                try? await NotificationManager.shared.scheduleFocusEnd(
                    sessionId: session.id,
                    focusTitle: session.focusTitle,
                    endDate: endDate
                )
            }
        }
        startedAt = session.startedAt
    }

    private func togglePause() {
        if isPaused {
            if let pausedAt = session.pausedAt {
                let delta = Int(Date().timeIntervalSince(pausedAt))
                if delta > 0 { session.pausedSeconds += delta }
            }
            session.pausedAt = nil
            isPaused = false

            do {
                try context.save()
                Haptics.success()
            } catch {
                Haptics.error()
                print("❌ Save failed (resumePause):", error)
            }

            recalcRemaining()

            Task {
                let endDate = Date().addingTimeInterval(TimeInterval(secondsRemaining))
                NotificationManager.shared.cancelFocusEnd(sessionId: session.id)
                try? await NotificationManager.shared.scheduleFocusEnd(
                    sessionId: session.id,
                    focusTitle: session.focusTitle,
                    endDate: endDate
                )
            }

        } else {
            session.pausedAt = Date()
            isPaused = true

            do {
                try context.save()
                Haptics.success()
            } catch {
                Haptics.error()
                print("❌ Save failed (pause):", error)
            }

            recalcRemaining()
            NotificationManager.shared.cancelFocusEnd(sessionId: session.id)
        }
    }

    private func recalcRemaining() {
        guard let startedAt else {
            secondsRemaining = session.durationSeconds
            return
        }

        let elapsed = Int(Date().timeIntervalSince(startedAt))

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
