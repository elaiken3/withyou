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
    @State private var step: Step = .setup

    @State private var focusTitle: String = ""
    @State private var focusStartStep: String = ""
    @State private var durationSeconds: Int = 45 * 60

    @State private var session: FocusSession?
    @State private var dumpText: String = ""
    
    @State private var showCustomDurationSheet = false
    @State private var customMinutes: Int = 25
    @State private var saveAsPreset: Bool = true
    @State private var presetLabel: String = ""
    
    @State private var activeProfile: UserProfile?
    @State private var presets: [FocusDurationPreset] = []

    enum Step { case setup, dump, running, review }

    var body: some View {
        NavigationStack {
            switch step {
            case .setup:
                setupView
            case .dump:
                dumpView
            case .running:
                if let s = session {
                    FocusTimerView(session: s) { step = .review }
                } else {
                    setupView
                }
            case .review:
                if let s = session {
                    FocusReviewView(session: s) {
                        step = .setup
                        session = nil
                    }
                } else {
                    setupView
                }
            }
        }
        .onAppear {
            // Ensure profile exists
            ProfileStore.ensureDefaultProfile(in: context)

            // Load active profile
            activeProfile = ProfileStore.activeProfile(in: context)

            // Set default duration + load presets
            if let p = activeProfile {
                durationSeconds = p.defaultFocusMinutes * 60
                presets = FocusPresetStore.presets(for: p.id, in: context)
            }

            // Resume active focus session if one exists
            loadActiveSessionIfNeeded()
        }
    }

    // MARK: - Views

    private var setupView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Focus Session").font(.largeTitle).bold()
            Text("Pick one thing. We’ll protect your attention for a short window.")
                .foregroundStyle(.secondary)

            TextField("Focus on… (e.g., Read Chapter 3)", text: $focusTitle)
                .textFieldStyle(.roundedBorder)

            TextField("Optional start step", text: $focusStartStep)
                .textFieldStyle(.roundedBorder)

            Text("Duration").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Text("Duration").font(.headline)

                // Presets row
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        // Default built-ins (keep your classics)
                        durationButton("25", 25 * 60)
                        durationButton("45", 45 * 60)
                        durationButton("60", 60 * 60)

                        // User presets (per profile)
                        ForEach(presets) { p in
                            durationButton(p.label, p.minutes * 60)
                        }

                        Button {
                            customMinutes = max(1, durationSeconds / 60)
                            presetLabel = ""
                            saveAsPreset = true
                            showCustomDurationSheet = true
                        } label: {
                            Label("Custom", systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .sheet(isPresented: $showCustomDurationSheet) {
                customDurationSheet
            }


            Button("Continue") {
                startSession()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(BorderedProminentButtonStyle())
            .disabled(focusTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
    }
    
    private var customDurationSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $customMinutes, in: 1...240, step: 1) {
                        Text("Minutes: \(customMinutes)")
                    }
                    Text("This will set your focus session to \(customMinutes) minutes.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Save as preset", isOn: $saveAsPreset)

                    if saveAsPreset {
                        TextField("Preset name (optional)", text: $presetLabel)
                        Text("Examples: “Deep work”, “Quick win”, “Reading”.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Custom Duration")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showCustomDurationSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Set") {
                        durationSeconds = customMinutes * 60

                        if saveAsPreset, let profile = activeProfile {
                            let label = presetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                            let finalLabel = label.isEmpty ? "\(customMinutes) min" : label

                            // Avoid duplicate minutes/label combos (simple guard)
                            let exists = presets.contains { $0.minutes == customMinutes && $0.label == finalLabel }
                            if !exists {
                                FocusPresetStore.addPreset(
                                    minutes: customMinutes,
                                    label: finalLabel,
                                    profileId: profile.id,
                                    in: context
                                )
                                presets = FocusPresetStore.presets(for: profile.id, in: context)
                            }
                        }

                        showCustomDurationSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private func durationButton(_ label: String, _ seconds: Int) -> some View {
        let isSelected = (durationSeconds == seconds)

        Button("\(label) min") { durationSeconds = seconds }
            .frame(maxWidth: .infinity)
            .modifier(ConditionalButtonStyle(isProminent: isSelected))
    }

    private var dumpView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Brain Dump").font(.largeTitle).bold()
            Text("What’s pulling at your attention? Park it here so you can focus.")
                .foregroundStyle(.secondary)

            HStack {
                TextField("Add a thought…", text: $dumpText)
                    .textFieldStyle(.roundedBorder)

                Button("Add") { addDumpItem() }
                    .buttonStyle(BorderedProminentButtonStyle())
                    .disabled(dumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let s = session {
                FocusDumpList(sessionId: s.id)
            }

            Button("Begin Focus") {
                // Ensure startedAt is set the moment we actually "begin"
                if let s = session, s.startedAt == nil {
                    s.startedAt = Date()
                    s.isActive = true
                    s.endedAt = nil
                    try? context.save()
                }
                step = .running
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(BorderedProminentButtonStyle())
            .disabled(session == nil)

            Text("You don’t need to remember these during this session.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func startSession() {
        // End existing active session (MVP)
        if let existing = FocusSessionStore.activeSession(in: context) {
            existing.isActive = false
            existing.endedAt = Date()
        }

        let title = focusTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        let s = FocusSession(
            focusTitle: title,
            focusStartStep: focusStartStep.trimmingCharacters(in: .whitespacesAndNewlines),
            durationSeconds: durationSeconds,
            createdAt: Date(),
            startedAt: nil,      // we set this on "Begin Focus"
            endedAt: nil,
            isActive: true
        )

        context.insert(s)
        do {
            try context.save()
            session = s
            step = .dump
        } catch {
            print("❌ Save failed (startSession):", error)
        }
    }

    private func addDumpItem() {
        guard let s = session else { return }
        let trimmed = dumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        context.insert(FocusDumpItem(text: trimmed, sessionId: s.id))

        do {
            try context.save()
            dumpText = ""
        } catch {
            print("❌ Save failed (addDumpItem):", error)
        }
    }

    private func loadActiveSessionIfNeeded() {
        guard session == nil else { return }

        if let existing = FocusSessionStore.activeSession(in: context) {
            session = existing
            step = (existing.startedAt == nil) ? .dump : .running
        }
    }
}

// MARK: - Dump list

private struct FocusDumpList: View {
    let sessionId: UUID

    @Query private var items: [FocusDumpItem]
    @Environment(\.modelContext) private var context

    init(sessionId: UUID) {
        self.sessionId = sessionId

        _items = Query(
            filter: #Predicate<FocusDumpItem> { (item: FocusDumpItem) in
                item.sessionId == sessionId
            },
            sort: [SortDescriptor<FocusDumpItem>(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            ForEach(items) { item in
                Text(item.text)
            }
            .onDelete { idx in
                for i in idx {
                    context.delete(items[i])
                }
                try? context.save()
            }
        }
        .frame(minHeight: 140)
    }
}
private struct ConditionalButtonStyle: ViewModifier {
    let isProminent: Bool
    func body(content: Content) -> some View {
        if isProminent {
            content.buttonStyle(BorderedProminentButtonStyle())
        } else {
            content.buttonStyle(BorderedButtonStyle())
        }
    }
}

