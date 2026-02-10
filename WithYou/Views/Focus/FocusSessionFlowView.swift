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
    
    init(selectedTab: Binding<AppTab>) {
        self._selectedTab = selectedTab
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

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
                            selectedTab = .today
                        }
                    } else {
                        setupView
                    }
                }
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
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)

            activeProfile = ProfileStore.activeProfile(in: context)

            if let p = activeProfile {
                durationSeconds = p.defaultFocusMinutes * 60
                presets = FocusPresetStore.presets(for: p.id, in: context)
            }

            loadActiveSessionIfNeeded()
        }
        .sheet(isPresented: $showCustomDurationSheet) {
            customDurationSheet
                .presentationBackground(Color.appBackground)
        }
    }

    // MARK: - Views

    private var setupView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Focus Session")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.appPrimaryText)

                    Text("Pick one thing. We’ll protect your attention for a short window.")
                        .foregroundStyle(.appSecondaryText)
                }

                // Title (card input)
                CardTextEditor(
                    placeholder: "Focus on… (e.g., Read Chapter 3)",
                    text: $focusTitle,
                    icon: "target",
                    minHeight: 80
                )

                // Optional start step (card input)
                CardTextEditor(
                    placeholder: "Optional start step",
                    text: $focusStartStep,
                    icon: "arrow.right.circle",
                    minHeight: 70
                )

                // Duration card
                VStack(alignment: .leading, spacing: 10) {
                    Text("Duration")
                        .font(.headline)
                        .foregroundStyle(.appPrimaryText)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            durationButton("25", 25 * 60)
                            durationButton("45", 45 * 60)
                            durationButton("60", 60 * 60)

                            ForEach(presets) { p in
                                durationButton(p.label, p.minutes * 60)
                            }

                            Button {
                                Haptics.tap()
                                customMinutes = max(1, durationSeconds / 60)
                                presetLabel = ""
                                saveAsPreset = true
                                showCustomDurationSheet = true
                            } label: {
                                Label("Custom", systemImage: "slider.horizontal.3")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 2)
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

                Button("Continue") {
                    Haptics.tap()
                    startSession()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .disabled(focusTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer(minLength: 24)
            }
            .padding()
        }
        .dismissKeyboardOnTap()
        .navigationTitle("Focus")
    }

    private var customDurationSheet: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                Form {
                    Section {
                        Stepper(value: $customMinutes, in: 1...240, step: 1) {
                            Text("Minutes: \(customMinutes)")
                                .foregroundStyle(.appPrimaryText)
                        }
                        Text("This will set your focus session to \(customMinutes) minutes.")
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
                        durationSeconds = customMinutes * 60

                        if saveAsPreset, let profile = activeProfile {
                            let label = presetLabel.trimmingCharacters(in: .whitespacesAndNewlines)
                            let finalLabel = label.isEmpty ? "\(customMinutes) min" : label

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

                        Haptics.success()
                        showCustomDurationSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
            .tint(.appAccent)
        }
    }

    @ViewBuilder
    private func durationButton(_ label: String, _ seconds: Int) -> some View {
        let isSelected = (durationSeconds == seconds)

        Button("\(label) min") {
            Haptics.tap()
            durationSeconds = seconds
        }
        .modifier(ConditionalButtonStyle(isProminent: isSelected))
        .tint(isSelected ? .appAccent : .appAccent)
        .accessibilityLabel("Set duration to \(label) minutes")
        .accessibilityHint(isSelected ? "Selected" : "Double tap to select")
    }

    private var dumpView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brain Dump")
                        .font(.largeTitle).bold()
                        .foregroundStyle(.appPrimaryText)

                    Text("What’s pulling at your attention? Park it here so you can focus.")
                        .foregroundStyle(.appSecondaryText)
                }

                // Add thought row as a card
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

                if let s = session {
                    FocusDumpList(sessionId: s.id)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
                        )
                }

                Button("Begin Focus") {
                    Haptics.tap()
                    if let s = session, s.startedAt == nil {
                        s.startedAt = Date()
                        s.isActive = true
                        s.endedAt = nil
                        do {
                            try context.save()
                            Haptics.success()
                        } catch {
                            Haptics.error()
                            print("❌ Save failed (beginFocus):", error)
                        }
                    } else {
                        Haptics.success()
                    }
                    step = .running
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .buttonStyle(.borderedProminent)
                .tint(.appAccent)
                .disabled(session == nil)

                Text("You don’t need to remember these during this session.")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)

                Spacer(minLength: 24)
            }
            .padding()
        }
        .navigationTitle("Focus")
    }

    // MARK: - Actions

    private func startSession() {
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
            startedAt: nil,
            endedAt: nil,
            isActive: true
        )

        context.insert(s)
        do {
            try context.save()
            Haptics.success()
            session = s
            step = .dump
        } catch {
            Haptics.error()
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
            Haptics.success()
            dumpText = ""
        } catch {
            Haptics.error()
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
                    .foregroundStyle(.appPrimaryText)
                    .listRowBackground(Color.appSurface)
            }
            .onDelete { idx in
                Haptics.tap()
                for i in idx {
                    context.delete(items[i])
                }
                do {
                    try context.save()
                    Haptics.success()
                } catch {
                    Haptics.error()
                    print("❌ Save failed (deleteDumpItem):", error)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.appSurface)
        .frame(minHeight: 160)
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
