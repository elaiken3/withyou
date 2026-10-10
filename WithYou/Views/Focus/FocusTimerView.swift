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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("keepScreenAwakeDuringFocus") private var keepScreenAwake: Bool = true

    let session: FocusSession
    /// Called once the session has ended. `completed` is true only for "I finished it".
    var onFinish: (_ completed: Bool) -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var timerFontSize: CGFloat = 56
    @ScaledMetric(relativeTo: .largeTitle) private var ringSize: CGFloat = 260
    @ScaledMetric(relativeTo: .body) private var ringLineWidth: CGFloat = 10

    @State private var now = Date()
    @State private var showAddThought = false
    @State private var thoughtText = ""
    @State private var showRefocus = false
    @State private var showTimeUpSheet = false
    @State private var didShowTimeUpSheet = false
    @State private var wrapUpAfterTimeUpSheet = false
    @State private var confirmEnd = false
    @State private var isEnding = false
    @State private var toast: Toast?

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(session: FocusSession, onFinish: @escaping (_ completed: Bool) -> Void) {
        self.session = session
        self.onFinish = onFinish
    }

    // MARK: - Derived time

    private var isPaused: Bool { session.pausedAt != nil }

    private var remaining: Int {
        FocusSessionStore.remainingSeconds(for: session, now: now)
    }

    private var overtime: Int {
        FocusSessionStore.overtimeSeconds(for: session, now: now)
    }

    private var isOverTime: Bool {
        session.startedAt != nil && remaining == 0
    }

    /// Fraction of the planned time that has passed (full once time is up).
    private var progress: Double {
        guard session.durationSeconds > 0 else { return 1 }
        let elapsed = Double(session.durationSeconds - remaining)
        return min(1, max(0, elapsed / Double(session.durationSeconds)))
    }

    private var timeText: String {
        isOverTime ? "+" + clock(overtime) : clock(remaining)
    }

    private var statusText: String {
        if isPaused { return "Paused. Resume whenever you’re ready." }
        if isOverTime { return "Extra time. Wrap up whenever you’re ready." }
        return "Only this matters right now."
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    timerRing
                        .padding(.top, 8)

                    Text(statusText)
                        .font(.body)
                        .foregroundStyle(.appSecondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    focusCard

                    controls

                    Spacer(minLength: 24)
                }
                .padding()
            }
        }
        .navigationTitle("Focus")
        .toast($toast)
        .onAppear {
            if session.startedAt == nil {
                // Normally "Begin Focus" already did this; it also schedules the end notification.
                try? FocusSessionStore.begin(session, in: context)
            }
            now = Date()
            updateIdleTimer()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: keepScreenAwake) {
            updateIdleTimer()
        }
        .onReceive(tick) { date in
            now = date
            checkForTimeUp()
        }
        .sheet(isPresented: $showAddThought) {
            addThoughtSheet
                .presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showRefocus) {
            RefocusView()
                .presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showTimeUpSheet, onDismiss: {
            if wrapUpAfterTimeUpSheet {
                wrapUpAfterTimeUpSheet = false
                confirmEnd = true
            }
        }) {
            timeUpSheet
                .presentationBackground(Color.appBackground)
        }
        .confirmationDialog(
            "How did it go?",
            isPresented: $confirmEnd,
            titleVisibility: .visible
        ) {
            Button("I finished it") {
                finish(completed: true)
            }

            Button("Stopping for now") {
                finish(completed: false)
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Stopping still counts.")
        }
        // Another screen needs its sheet up (see `AppRouter.closeAllSheets()`). A thought
        // being typed stays in `thoughtText`.
        .onChange(of: AppRouter.shared.closeSheetsRequest) { _, _ in
            wrapUpAfterTimeUpSheet = false
            showAddThought = false
            showRefocus = false
            showTimeUpSheet = false
            confirmEnd = false
        }
    }

    // MARK: - Pieces

    private var timerRing: some View {
        ZStack {
            Circle()
                .stroke(Color.appHairline.opacity(0.15), lineWidth: ringLineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    Color.appAccent.opacity(isOverTime ? 0.55 : 1),
                    style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)

            VStack(spacing: 4) {
                Text(timeText)
                    .font(.system(size: timerFontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: !isOverTime))
                    .animation(reduceMotion ? nil : .default, value: timeText)
                    .foregroundStyle(.appPrimaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)

                Text(isPaused ? "paused" : (isOverTime ? "extra time" : "left"))
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(ringLineWidth * 2.5)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: ringSize)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOverTime ? "Extra time" : "Time left")
        .accessibilityValue(spokenTimeValue)
    }

    private var spokenTimeValue: String {
        let spoken = spokenDuration(isOverTime ? overtime : remaining)
        return isPaused ? "\(spoken), paused" : spoken
    }

    private var focusCard: some View {
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
        .cardStyle()
    }

    /// 2×2 grid; stacks vertically when large text sizes would not fit two across.
    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    pauseButton
                    refocusButton
                }
                GridRow {
                    addThoughtButton
                    endButton
                }
            }

            VStack(spacing: 10) {
                pauseButton
                refocusButton
                addThoughtButton
                endButton
            }
        }
        .tint(.appAccent)
    }

    private var pauseButton: some View {
        Button {
            Haptics.tap()
            togglePause()
        } label: {
            Label(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isEnding)
    }

    private var refocusButton: some View {
        Button {
            Haptics.tap()
            showRefocus = true
        } label: {
            Label("Refocus", systemImage: "wind")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("A one-minute breathing reset")
    }

    private var addThoughtButton: some View {
        Button {
            Haptics.tap()
            showAddThought = true
        } label: {
            Label("Add thought", systemImage: "brain")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .accessibilityHint("Park a thought for after this session")
    }

    private var endButton: some View {
        Button {
            Haptics.tap()
            confirmEnd = true
        } label: {
            Label("End", systemImage: "checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isEnding)
        .accessibilityHint("Finish or stop this session")
    }

    // MARK: - Sheets

    private var addThoughtSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Park a thought")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.appPrimaryText)
                            .accessibilityAddTraits(.isHeader)

                        Text("It’ll be waiting for you after this session.")
                            .foregroundStyle(.appSecondaryText)

                        CardTextEditor(
                            placeholder: "Type or dictate…",
                            text: $thoughtText,
                            icon: "brain",
                            minHeight: 120
                        )

                        Button {
                            Haptics.tap()
                            saveThought()
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.appAccent)
                        .disabled(thoughtText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
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

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Time’s up. That counted.")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.appPrimaryText)
                            .accessibilityAddTraits(.isHeader)

                        Text("Extend a little, keep going, or wrap up. Any of these is fine.")
                            .foregroundStyle(.appSecondaryText)

                        Button {
                            Haptics.tap()
                            extend(byMinutes: 5)
                            showTimeUpSheet = false
                        } label: {
                            Label("Extend 5 min", systemImage: "plus.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.appAccent)

                        Button {
                            Haptics.tap()
                            showTimeUpSheet = false
                        } label: {
                            Label("Keep going", systemImage: "forward")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)

                        Button {
                            Haptics.tap()
                            // The end dialog opens once this sheet has finished closing.
                            wrapUpAfterTimeUpSheet = true
                            showTimeUpSheet = false
                        } label: {
                            Label("Wrap up", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                    .padding()
                }
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
        .presentationDetents([.medium, .large])
    }

    // MARK: - Session actions

    private func checkForTimeUp() {
        guard !isPaused, !isEnding, session.startedAt != nil else { return }

        if remaining > 0 {
            didShowTimeUpSheet = false
            return
        }

        // Show the sheet once per time-up, and only when nothing else is on screen.
        guard !didShowTimeUpSheet, !showAddThought, !showRefocus, !confirmEnd else { return }
        didShowTimeUpSheet = true
        showTimeUpSheet = true
    }

    private func finish(completed: Bool) {
        guard !isEnding else { return }
        isEnding = true

        showTimeUpSheet = false
        showAddThought = false
        showRefocus = false
        UIApplication.shared.isIdleTimerDisabled = false

        if completed {
            CompletionStore.completeFromSession(session, in: context)
        } else {
            CompletionStore.endWithoutCompleting(session, in: context)
        }

        Haptics.success()
        onFinish(completed)
    }

    private func saveThought() {
        let trimmed = thoughtText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        context.insert(FocusDumpItem(text: trimmed, sessionId: session.id))
        do {
            try context.save()
            Haptics.success()
            thoughtText = ""
            showAddThought = false
            toast = Toast(text: "Parked. It’ll be here after.")
        } catch {
            print("❌ Save failed (addThought):", error)
        }
    }

    private func extend(byMinutes minutes: Int) {
        let current = Date()
        // Time already spent, excluding pauses. Extending from here means the extra
        // minutes start now, even when already past the planned end.
        let spent = session.durationSeconds
            - FocusSessionStore.remainingSeconds(for: session, now: current)
            + FocusSessionStore.overtimeSeconds(for: session, now: current)
        session.durationSeconds = max(0, spent) + minutes * 60

        do {
            try context.save()
            Haptics.success()
        } catch {
            print("❌ Save failed (extend):", error)
            return
        }

        now = current
        didShowTimeUpSheet = false
        FocusSessionStore.scheduleEndNotification(for: session)
    }

    private func togglePause() {
        let current = Date()

        if let pausedAt = session.pausedAt {
            session.pausedSeconds += max(0, Int(current.timeIntervalSince(pausedAt)))
            session.pausedAt = nil
        } else {
            session.pausedAt = current
        }

        do {
            try context.save()
        } catch {
            print("❌ Save failed (togglePause):", error)
        }

        now = current
        // Cancels while paused; reschedules for the remaining time after resuming.
        FocusSessionStore.scheduleEndNotification(for: session)
        updateIdleTimer()
    }

    /// Keeps the screen on while the timer is running (if the person wants that).
    private func updateIdleTimer() {
        let running = session.isActive
            && session.endedAt == nil
            && session.startedAt != nil
            && !isPaused
            && !isEnding
        UIApplication.shared.isIdleTimerDisabled = keepScreenAwake && running
    }

    /// "12 minutes 30 seconds" for VoiceOver.
    private func spokenDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append(h == 1 ? "1 hour" : "\(h) hours") }
        if m > 0 { parts.append(m == 1 ? "1 minute" : "\(m) minutes") }
        if s > 0 || parts.isEmpty { parts.append(s == 1 ? "1 second" : "\(s) seconds") }
        return parts.joined(separator: " ")
    }

    private func clock(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
