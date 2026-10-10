//
//  FocusSessionFlowView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct FocusSessionFlowView: View {
    @Environment(\.modelContext) private var context
    @Binding var selectedTab: AppTab

    /// Sessions can be started from Today, "I'm stuck", a notification or Siri while this
    /// tab is already on screen, so the active session is observed rather than fetched once.
    @Query private var activeSessions: [FocusSession]

    @State private var step: Step = .setup

    @State private var focusTitle: String = ""
    @State private var focusStartStep: String = ""
    @State private var durationSeconds: Int = 45 * 60
    @State private var userPickedDuration = false

    @State private var session: FocusSession?
    @State private var sessionCompleted = false
    @State private var dumpText: String = ""

    @State private var showCustomDurationSheet = false
    @State private var customMinutes: Int = 25
    @State private var saveAsPreset: Bool = true
    @State private var presetLabel: String = ""

    @State private var activeProfile: UserProfile?
    @State private var presets: [FocusDurationPreset] = []

    @State private var toast: Toast?

    enum Step { case setup, dump, running, review }

    private static let builtInMinutes: [Int] = [25, 45, 60]

    init(selectedTab: Binding<AppTab>) {
        self._selectedTab = selectedTab
        _activeSessions = Query(
            filter: #Predicate<FocusSession> { (s: FocusSession) in
                s.isActive && s.endedAt == nil
            },
            sort: [SortDescriptor<FocusSession>(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                content
            }
            .tint(.appAccent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
        }
        .toast($toast)
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
            loadProfileDefaults()
            syncWithActiveSession()
            rescueOrphanedThoughts()
        }
        .onChange(of: activeSessions.first?.id) {
            syncWithActiveSession()
        }
        .sheet(isPresented: $showCustomDurationSheet) {
            customDurationSheet
                .presentationBackground(Color.appBackground)
        }
        // Another screen needs its sheet up (see `AppRouter.closeAllSheets()`).
        .onChange(of: AppRouter.shared.closeSheetsRequest) { _, _ in
            showCustomDurationSheet = false
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .setup:
            setupView
        case .dump:
            if session != nil {
                dumpView
            } else {
                setupView
            }
        case .running:
            if let s = session {
                FocusTimerView(session: s) { completed in
                    sessionCompleted = completed
                    step = .review
                }
                .id(s.id)
            } else {
                setupView
            }
        case .review:
            if let s = session {
                FocusReviewView(session: s, completed: sessionCompleted) {
                    finishReview()
                }
                .id(s.id)
            } else {
                setupView
            }
        }
    }

    // MARK: - Setup

    private var trimmedTitle: String {
        focusTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Focus Session")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.appPrimaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("Pick one thing. We’ll protect your attention for a short window.")
                        .foregroundStyle(.appSecondaryText)
                }

                CardTextEditor(
                    placeholder: "Focus on… (e.g., Read Chapter 3)",
                    text: $focusTitle,
                    icon: "target",
                    minHeight: 80
                )

                CardTextEditor(
                    placeholder: "Optional start step",
                    text: $focusStartStep,
                    icon: "arrow.right.circle",
                    minHeight: 70
                )

                durationCard

                Button {
                    Haptics.tap()
                    startSession()
                } label: {
                    Text("Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.appAccent)
                .disabled(trimmedTitle.isEmpty)

                Spacer(minLength: 24)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .navigationTitle("Focus")
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Duration")
                .font(.headline)
                .foregroundStyle(.appPrimaryText)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Self.builtInMinutes, id: \.self) { minutes in
                        durationChip(minutes: minutes)
                    }

                    ForEach(customPresets) { preset in
                        durationChip(minutes: preset.minutes, name: presetName(preset))
                    }

                    // A duration set without saving a preset (or a profile default like 30)
                    // still gets a visible, selected chip.
                    if let unlisted = unlistedSelectedMinutes {
                        durationChip(minutes: unlisted)
                    }

                    Button {
                        Haptics.tap()
                        customMinutes = min(180, max(1, durationSeconds / 60))
                        presetLabel = ""
                        saveAsPreset = true
                        showCustomDurationSheet = true
                    } label: {
                        Label("Custom", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Choose any length from 1 to 180 minutes")
                }
                .padding(.vertical, 2)
            }
        }
        .cardStyle()
    }

    /// Saved presets, minus any whose minutes repeat 25/45/60 or an earlier preset.
    private var customPresets: [FocusDurationPreset] {
        var seen = Set(Self.builtInMinutes)
        var result: [FocusDurationPreset] = []
        for preset in presets where !seen.contains(preset.minutes) {
            seen.insert(preset.minutes)
            result.append(preset)
        }
        return result
    }

    private var unlistedSelectedMinutes: Int? {
        let minutes = durationSeconds / 60
        guard minutes > 0 else { return nil }
        let listed = Set(Self.builtInMinutes).union(customPresets.map { $0.minutes })
        return listed.contains(minutes) ? nil : minutes
    }

    /// The preset's own name ("Deep work"), or nil when it is just "50 min".
    private func presetName(_ preset: FocusDurationPreset) -> String? {
        let label = preset.label.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty || label == "\(preset.minutes) min" { return nil }
        return label
    }

    @ViewBuilder
    private func durationChip(minutes: Int, name: String? = nil) -> some View {
        let isSelected = durationSeconds == minutes * 60
        let title = name.map { "\($0) · \(minutes) min" } ?? "\(minutes) min"
        let spoken = name.map { "\($0), \(minutes) minutes" } ?? "\(minutes) minutes"

        Button {
            Haptics.tap()
            durationSeconds = minutes * 60
            userPickedDuration = true
        } label: {
            Text(title)
        }
        .modifier(ConditionalButtonStyle(isProminent: isSelected))
        .tint(.appAccent)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var customDurationSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                Form {
                    Section {
                        Picker("Minutes", selection: $customMinutes) {
                            ForEach(1...180, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .pickerStyle(.wheel)
                        .labelsHidden()
                    } footer: {
                        Text("Your session will be \(customMinutes) minutes.")
                            .foregroundStyle(.appSecondaryText)
                    }

                    Section {
                        Toggle("Save as preset", isOn: $saveAsPreset)
                            .tint(.appAccent)

                        if saveAsPreset {
                            TextField("Preset name (optional)", text: $presetLabel)
                            Text("Examples: “Deep work”, “Quick win”, “Reading”.")
                                .foregroundStyle(.appSecondaryText)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Custom Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Haptics.tap()
                        showCustomDurationSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") {
                        Haptics.tap()
                        applyCustomDuration()
                        showCustomDurationSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(.appAccent)
        }
    }

    // MARK: - Brain dump

    private var dumpView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brain Dump")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.appPrimaryText)
                        .accessibilityAddTraits(.isHeader)

                    Text("What’s pulling at your attention? Park it here so you can focus.")
                        .foregroundStyle(.appSecondaryText)
                }

                VStack(alignment: .leading, spacing: 10) {
                    CardTextEditor(
                        placeholder: "Add a thought…",
                        text: $dumpText,
                        icon: "tray.full",
                        minHeight: 70
                    )

                    Button("Add") {
                        Haptics.tap()
                        addDumpItem()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.appAccent)
                    .disabled(dumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .cardStyle()

                if let s = session {
                    FocusDumpList(sessionId: s.id) { item in
                        removeThought(item)
                    }
                }

                Button {
                    Haptics.tap()
                    beginFocus()
                } label: {
                    Text("Begin Focus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.appAccent)
                .disabled(session == nil)

                Text("Anything parked here waits for you after. Nothing to park? Begin anyway.")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)

                Spacer(minLength: 24)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Focus")
    }

    // MARK: - Actions

    private func loadProfileDefaults() {
        activeProfile = ProfileStore.activeProfile(in: context)

        guard let profile = activeProfile else { return }
        presets = FocusPresetStore.presets(for: profile.id, in: context)

        if !userPickedDuration {
            durationSeconds = max(1, profile.defaultFocusMinutes) * 60
        }
    }

    private func applyCustomDuration() {
        let minutes = min(180, max(1, customMinutes))
        durationSeconds = minutes * 60
        userPickedDuration = true

        if saveAsPreset, let profile = activeProfile, !Self.builtInMinutes.contains(minutes) {
            let label = presetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalLabel = label.isEmpty ? "\(minutes) min" : label

            let exists = presets.contains { $0.minutes == minutes && $0.label == finalLabel }
            if !exists {
                FocusPresetStore.addPreset(
                    minutes: minutes,
                    label: finalLabel,
                    profileId: profile.id,
                    in: context
                )
                presets = FocusPresetStore.presets(for: profile.id, in: context)
            }
        }

        Haptics.success()
    }

    private func startSession() {
        let title = trimmedTitle
        guard !title.isEmpty else { return }

        do {
            let s = try FocusSessionStore.start(
                title: title,
                startStep: focusStartStep.trimmingCharacters(in: .whitespacesAndNewlines),
                durationSeconds: durationSeconds,
                beginImmediately: false,
                in: context
            )
            Haptics.success()
            session = s
            step = .dump
        } catch {
            print("❌ Save failed (startSession):", error)
        }
    }

    private func beginFocus() {
        guard let s = session else { return }
        do {
            // Sets startedAt (if needed) and schedules the "Focus time is up" notification.
            try FocusSessionStore.begin(s, in: context)
            Haptics.success()
            step = .running
        } catch {
            print("❌ Save failed (beginFocus):", error)
        }
    }

    private func addDumpItem() {
        guard let s = session else { return }
        let trimmed = dumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        context.insert(FocusDumpItem(text: trimmed, sessionId: s.id))

        do {
            try context.save()
            Haptics.success()
            dumpText = ""
        } catch {
            print("❌ Save failed (addDumpItem):", error)
        }
    }

    private func removeThought(_ item: FocusDumpItem) {
        Haptics.tap()
        let text = item.text
        let sessionId = item.sessionId
        let createdAt = item.createdAt

        context.delete(item)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (removeThought):", error)
            return
        }

        toast = Toast(text: "Removed.", actionTitle: "Undo", action: {
            context.insert(FocusDumpItem(text: text, sessionId: sessionId, createdAt: createdAt))
            try? context.save()
        })
    }

    private func finishReview() {
        step = .setup
        session = nil
        sessionCompleted = false
        focusTitle = ""
        focusStartStep = ""
        dumpText = ""
        userPickedDuration = false
        loadProfileDefaults()
        // A session may have been started elsewhere while this one was wrapping up.
        syncWithActiveSession()
        selectedTab = .today
    }

    /// Keeps the flow in step with the active session, wherever it was started or ended.
    private func syncWithActiveSession() {
        let active = activeSessions.first

        switch step {
        case .review:
            // Wrapping up an ended session; leave it alone.
            return

        case .setup:
            if let active {
                load(active)
            }

        case .dump, .running:
            if let active {
                if active.id != session?.id {
                    // A new session was started somewhere else.
                    load(active)
                    rescueOrphanedThoughts()
                }
            } else if let current = session, current.isActive, current.endedAt == nil {
                // Still active; the query just hasn't caught up.
                return
            } else {
                // The session ended somewhere else (for example, from Today).
                session = nil
                step = .setup
                rescueOrphanedThoughts()
            }
        }
    }

    private func load(_ active: FocusSession) {
        session = active
        sessionCompleted = false
        step = (active.startedAt == nil) ? .dump : .running
    }

    private func rescueOrphanedThoughts() {
        let keep: UUID? = (step == .review) ? session?.id : nil
        let moved = CompletionStore.rescueOrphanedThoughts(keepingSessionId: keep, in: context)
        if moved > 0 {
            toast = Toast(text: "Thoughts from an earlier session are in your Inbox.")
        }
    }
}

// MARK: - Dump list

private struct FocusDumpList: View {
    let sessionId: UUID
    var onRemove: (FocusDumpItem) -> Void

    @Query private var items: [FocusDumpItem]

    init(sessionId: UUID, onRemove: @escaping (FocusDumpItem) -> Void) {
        self.sessionId = sessionId
        self.onRemove = onRemove

        _items = Query(
            filter: #Predicate<FocusDumpItem> { (item: FocusDumpItem) in
                item.sessionId == sessionId
            },
            sort: [SortDescriptor<FocusDumpItem>(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        if !items.isEmpty {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.text)
                            .foregroundStyle(.appPrimaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            onRemove(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.body)
                                .foregroundStyle(.appSecondaryText)
                                .frame(minWidth: 44, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove thought")
                    }
                    .cardStyle(padding: 10)
                }
            }
        }
    }
}

private struct ConditionalButtonStyle: ViewModifier {
    let isProminent: Bool
    func body(content: Content) -> some View {
        if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}
