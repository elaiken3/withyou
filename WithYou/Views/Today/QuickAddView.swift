//
//  QuickAddView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftUI
import SwiftData

/// Capture: a relief valve, not a commitment.
///
/// Used as the Capture tab (`showsCloseButton == false`: no Cancel/Close, a toast with Undo
/// after saving) and as a sheet from the Inbox (`showsCloseButton == true`: one "Close",
/// and saving simply dismisses).
///
/// "Save" is instant and rule-based. "Sort it out for me" asks AI to split and time the
/// text, and "Speak" opens voice capture; both end in a review, so nothing is saved
/// without the person seeing it first.
struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showsCloseButton: Bool

    @FocusState private var isTextFocused: Bool
    @FocusState private var isFirstStepFocused: Bool

    @State private var text: String = ""
    @State private var startStepText: String = ""
    @State private var showFirstStep: Bool = false

    @State private var isSaving = false
    @State private var lastErrorMessage: String?
    @State private var destination: Destination?
    @State private var toast: Toast?

    @State private var showVoiceCapture = false
    @State private var isSorting = false
    @State private var reviewRequest: CaptureReviewRequest?
    /// What a review or voice capture saved; finished off once its sheet has closed.
    @State private var pendingBatch: PendingBatch?

    private let parser = CaptureParser()

    init(showsCloseButton: Bool = false) {
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {

                        // Main capture input (multi-line)
                        CardTextEditor(
                            placeholder: "Type or dictate… (e.g., “Email landlord tomorrow morning”)",
                            text: $text,
                            icon: "sparkles",
                            minHeight: 120
                        )
                        .focused($isTextFocused)

                        // Where "Save" will put it (updated as the person types), and the mic.
                        destinationAndVoiceRow

                        firstStepToggle

                        if showFirstStep {
                            CardTextEditor(
                                placeholder: "First step (e.g., Open the doc)",
                                text: $startStepText,
                                icon: "arrow.right.circle",
                                minHeight: 80
                            )
                            .focused($isFirstStepFocused)
                        }

                        if let msg = lastErrorMessage {
                            Text(msg)
                                .foregroundStyle(.appSecondaryText)
                                .font(.footnote)
                        }

                        saveButtons
                            .padding(.top, 4)

                        if !isTextEmpty {
                            sortButton
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isTextFocused = false
                isFirstStepFocused = false
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") {
                            Haptics.tap()
                            dismiss()
                        }
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isTextFocused = false
                        isFirstStepFocused = false
                    }
                }
            }
            .tint(.appAccent)
            .toast($toast)
            .sheet(isPresented: $showVoiceCapture, onDismiss: finishPendingBatch) {
                VoiceCaptureView(initialText: text) { summary in
                    pendingBatch = PendingBatch(summary: summary, text: text, step: startStepText)
                }
            }
            .sheet(item: $reviewRequest, onDismiss: finishPendingBatch) { request in
                NavigationStack {
                    CaptureReviewView(
                        suggestions: request.suggestions,
                        source: request.source,
                        itemSource: .app,
                        onClose: { reviewRequest = nil }
                    ) { summary in
                        pendingBatch = PendingBatch(summary: summary, text: text, step: startStepText)
                        reviewRequest = nil
                    }
                }
            }
            .onAppear {
                Task {
                    try? await Task.sleep(for: .milliseconds(50))
                    isTextFocused = true
                }
            }
            // Debounced preview: restarts on every keystroke, settles after ~0.3 s.
            .task(id: text) {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let next = previewDestination(for: text)
                guard next != destination else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                    destination = next
                }
            }
        }
    }

    // MARK: - Pieces

    private var firstStepToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut) { showFirstStep.toggle() }
            let showing = showFirstStep
            Task {
                try? await Task.sleep(for: .milliseconds(50))
                if showing {
                    isFirstStepFocused = true
                } else {
                    isTextFocused = true
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(showFirstStep ? "Hide first step" : "Add a first step (optional)")
                    .foregroundStyle(.appPrimaryText)
                Spacer(minLength: 8)
                Image(systemName: showFirstStep ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.appSecondaryText)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The destination chip on the left, "Speak" on the right; stacked at larger text sizes.
    private var destinationAndVoiceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                if let destination {
                    destinationChip(destination)
                        .transition(.opacity)
                }
                Spacer(minLength: 8)
                voiceButton
            }
            VStack(alignment: .leading, spacing: 8) {
                if let destination {
                    destinationChip(destination)
                        .transition(.opacity)
                }
                voiceButton
            }
        }
    }

    private var voiceButton: some View {
        Button {
            Haptics.tap()
            isTextFocused = false
            isFirstStepFocused = false
            showVoiceCapture = true
        } label: {
            Label("Speak", systemImage: "mic.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .disabled(isSaving || isSorting)
        .accessibilityLabel("Voice capture")
        .accessibilityHint("Say what’s on your mind. You’ll look it over before anything is saved.")
    }

    /// AI (or the rules) splits and times the text; a review opens before anything is saved.
    private var sortButton: some View {
        Button {
            Haptics.tap()
            sortItOut()
        } label: {
            HStack(spacing: 6) {
                if isSorting {
                    ProgressView()
                } else {
                    Image(systemName: "wand.and.stars")
                        .accessibilityHidden(true)
                }
                Text(isSorting ? "Sorting it out…" : "Sort it out for me")
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .disabled(isSaving || isSorting)
        .accessibilityHint("Splits it into separate things and suggests times. You look it over before anything is saved.")
    }

    private func destinationChip(_ destination: Destination) -> some View {
        Text(destination.chipText)
            .font(.footnote)
            .foregroundStyle(.appSecondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(.appSurface)
            )
            .overlay(
                Capsule().stroke(.appHairline.opacity(0.10), lineWidth: 1)
            )
            .accessibilityLabel(destination.spokenText)
    }

    /// Side by side when they fit; stacked at larger text sizes.
    private var saveButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                saveButton
                inboxOnlyButton
            }
            VStack(spacing: 10) {
                saveButton
                inboxOnlyButton
            }
        }
        .tint(.appAccent)
    }

    private var saveButton: some View {
        Button {
            Haptics.tap()
            save(mode: .smart)
        } label: {
            Text("Save")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSaveDisabled)
    }

    private var inboxOnlyButton: some View {
        Button {
            Haptics.tap()
            save(mode: .inboxOnly)
        } label: {
            Text("Inbox only")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(isSaveDisabled)
        .accessibilityHint("Saves without scheduling")
    }

    // MARK: - Destination preview

    private enum Destination: Equatable {
        case inbox
        case scheduled(Date)
        case focusDump

        var chipText: String {
            switch self {
            case .inbox:
                return "→ Inbox"
            case .scheduled(let date):
                return "→ \(date.friendlyDayTime)"
            case .focusDump:
                return "→ Focus brain dump"
            }
        }

        var spokenText: String {
            switch self {
            case .inbox:
                return "Save goes to your Inbox"
            case .scheduled(let date):
                return "Save schedules it for \(date.friendlyDayTime)"
            case .focusDump:
                return "Save parks it in your focus session"
            }
        }
    }

    /// Where "Save" would put `raw` right now. Same rules as `save(mode: .smart)`.
    private func previewDestination(for raw: String) -> Destination? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let profile = ProfileStore.activeProfile(in: context)
        if FocusSessionStore.activeSession(in: context) != nil,
           profile?.routeSiriToFocusDumpWhenActive ?? true {
            return .focusDump
        }
        if let when = parser.parse(trimmed, profile: profile).scheduledAt {
            return .scheduled(when)
        }
        return .inbox
    }

    // MARK: - Saving

    private var isTextEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isSaveDisabled: Bool {
        isSaving || isSorting || isTextEmpty
    }

    private enum SaveMode {
        case smart
        case inboxOnly
    }

    /// What a save created, so Undo can remove exactly that.
    private enum Created {
        case inbox(UUID)
        case reminder(UUID)
        case focusDump(UUID)
        /// Several items saved from a review.
        case batch(CaptureSaveSummary)
    }

    /// A review or voice capture that saved, plus the words to put back on Undo.
    private struct PendingBatch {
        let summary: CaptureSaveSummary
        let text: String
        let step: String
    }

    private func save(mode: SaveMode) {
        // `isSaving` stays true until every path (including the async scheduling one)
        // has finished, so a double tap can't save twice.
        guard !isSaving else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }

        isSaving = true
        lastErrorMessage = nil

        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)
        let trimmedStep = startStepText.trimmingCharacters(in: .whitespacesAndNewlines)

        // While focusing, "Save" parks the thought in the session's brain dump (if enabled).
        // "Inbox only" always means the Inbox.
        if mode == .smart,
           let active = FocusSessionStore.activeSession(in: context),
           profile?.routeSiriToFocusDumpWhenActive ?? true {

            let payload: String
            if trimmedStep.isEmpty {
                payload = trimmedText
            } else {
                payload =
                """
                \(trimmedText)
                Start: \(trimmedStep)
                """
            }

            let dumpItem = FocusDumpItem(text: payload, sessionId: active.id)
            context.insert(dumpItem)
            do {
                try context.save()
                finishSave(created: .focusDump(dumpItem.id), message: "Parked in your focus session.")
            } catch {
                context.delete(dumpItem)
                print("❌ Save failed (FocusDump):", error)
                failSave("Couldn’t save that just now. Try again.")
            }
            return
        }

        let parsed = parser.parse(trimmedText, profile: profile)
        let startStepToUse = trimmedStep.isEmpty ? parsed.startStep : trimmedStep

        // Smart mode: schedule if a time was mentioned.
        if mode == .smart, let when = parsed.scheduledAt {
            Task {
                do {
                    let reminder = try await ReminderStore.createAndSchedule(
                        title: parsed.title,
                        startStep: startStepToUse,
                        estimateMinutes: parsed.estimateMinutes,
                        scheduledAt: when,
                        in: context
                    )
                    finishSave(created: .reminder(reminder.id), message: "Scheduled for \(when.friendlyDayTime).")
                } catch {
                    print("❌ Save failed (schedule):", error)
                    failSave("Couldn’t schedule that just now. Try again.")
                }
            }
            return
        }

        let inbox = InboxItem(
            content: trimmedText,
            title: parsed.title,
            source: .app,
            startStep: startStepToUse,
            estimateMinutes: parsed.estimateMinutes
        )
        context.insert(inbox)

        do {
            try context.save()
            finishSave(created: .inbox(inbox.id), message: "Saved to Inbox.")
        } catch {
            context.delete(inbox)
            print("❌ Save failed (Inbox):", error)
            failSave("Couldn’t save to Inbox just now. Try again.")
        }
    }

    private func finishSave(created: Created, message: String) {
        Haptics.success()
        let savedText = text
        let savedStep = startStepText

        resetFields()
        isSaving = false

        // Sheet: just close. The person came here from somewhere else.
        if showsCloseButton {
            dismiss()
            return
        }

        isTextFocused = false
        isFirstStepFocused = false
        toast = Toast(text: message, actionTitle: "Undo", action: {
            undo(created, restoringText: savedText, step: savedStep)
        })
    }

    // MARK: - Sort it out / voice

    private func sortItOut() {
        guard !isSorting, !isSaving else { return }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        let trimmedStep = startStepText.trimmingCharacters(in: .whitespacesAndNewlines)

        isSorting = true
        lastErrorMessage = nil
        isTextFocused = false
        isFirstStepFocused = false

        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        Task {
            let result = await AIService.capture(trimmedText, context: CaptureContext.current(profile: profile))
            var suggestions = result.value
            var source = result.source
            if suggestions.isEmpty {
                suggestions = CaptureSaver.rulesSuggestions(for: trimmedText, profile: profile)
                source = .rules
            }
            // A first step the person typed beats a suggested one.
            if !trimmedStep.isEmpty, suggestions.count == 1 {
                suggestions[0].firstStep = trimmedStep
            }
            isSorting = false
            reviewRequest = CaptureReviewRequest(suggestions: suggestions, source: source)
        }
    }

    /// Ends a review or voice capture save the same way as a plain save.
    private func finishPendingBatch() {
        guard let batch = pendingBatch else { return }
        pendingBatch = nil

        // The editor's words went into what was saved.
        resetFields()

        if showsCloseButton {
            dismiss()
            return
        }

        isTextFocused = false
        isFirstStepFocused = false
        toast = Toast(text: CaptureSaver.message(for: batch.summary), actionTitle: "Undo", action: {
            undo(.batch(batch.summary), restoringText: batch.text, step: batch.step)
        })
    }

    private func failSave(_ message: String) {
        Haptics.error()
        lastErrorMessage = message
        isSaving = false
    }

    private func resetFields() {
        text = ""
        startStepText = ""
        showFirstStep = false
        lastErrorMessage = nil
        destination = nil
    }

    /// Removes what the last save created and puts the words back, so nothing is lost.
    private func undo(_ created: Created, restoringText savedText: String, step savedStep: String) {
        switch created {
        case .inbox(let id):
            var descriptor = FetchDescriptor<InboxItem>(
                predicate: #Predicate<InboxItem> { (item: InboxItem) in item.id == id }
            )
            descriptor.fetchLimit = 1
            if let item = (try? context.fetch(descriptor))?.first {
                context.delete(item)
                try? context.save()
            }

        case .reminder(let id):
            var descriptor = FetchDescriptor<VerboseReminder>(
                predicate: #Predicate<VerboseReminder> { (reminder: VerboseReminder) in reminder.id == id }
            )
            descriptor.fetchLimit = 1
            if let reminder = (try? context.fetch(descriptor))?.first {
                // Cancels the pending notification too.
                try? ReminderStore.letGo(reminder, in: context)
            } else {
                NotificationManager.shared.cancelReminder(id: id)
            }

        case .focusDump(let id):
            var descriptor = FetchDescriptor<FocusDumpItem>(
                predicate: #Predicate<FocusDumpItem> { (item: FocusDumpItem) in item.id == id }
            )
            descriptor.fetchLimit = 1
            if let item = (try? context.fetch(descriptor))?.first {
                context.delete(item)
                try? context.save()
            }

        case .batch(let summary):
            CaptureSaver.undo(summary, in: context)
        }

        // Only refill the editor if the person hasn't started typing something new.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text = savedText
            startStepText = savedStep
            showFirstStep = !savedStep.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
