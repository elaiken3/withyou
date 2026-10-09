//
//  VoiceCaptureView.swift
//  WithYou
//
//  Say what's on your mind. WithYou writes it down as you talk, then sorts it into
//  items you look over before anything is saved.
//

import Foundation
import SwiftUI
import SwiftData
import UIKit

struct VoiceCaptureView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called with what was saved, just before the sheet closes, so the presenter can
    /// show a toast with Undo.
    let onSaved: (CaptureSaveSummary) -> Void

    @State private var transcriber = SpeechTranscriber()
    @State private var draft = ""
    @State private var isSorting = false
    @State private var showReview = false
    @State private var reviewSuggestions: [CaptureSuggestion] = []
    @State private var reviewSource: AISource = .rules
    @State private var hint = VoiceCaptureView.hints.randomElement() ?? VoiceCaptureView.hints[0]

    @FocusState private var isEditorFocused: Bool
    @ScaledMetric(relativeTo: .title) private var micDiameter: CGFloat = 96

    /// `initialText` is anything already typed; new words are added after it.
    init(initialText: String = "", onSaved: @escaping (CaptureSaveSummary) -> Void = { _ in }) {
        self.onSaved = onSaved
        _draft = State(initialValue: initialText)
    }

    private static let hints = [
        "Try: “Call the dentist tomorrow morning, buy oat milk, and finish the slides by Friday.”",
        "Say it the way it comes. You can sort it out after.",
        "Lists work well: “Water the plants, email Sam, and book the car service.”"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        micButton
                            .padding(.top, 8)

                        Text(statusText)
                            .font(.subheadline)
                            .foregroundStyle(.appSecondaryText)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)

                        if let issue = transcriber.issue {
                            issueCard(issue)
                        }

                        transcriptArea

                        if isDraftEmpty && transcriber.issue == nil {
                            Text(hint)
                                .font(.footnote)
                                .foregroundStyle(.appSecondaryText)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if transcriber.isOnDevice {
                            Label("Your voice is turned into text on this iPhone.", systemImage: "lock")
                                .font(.footnote)
                                .foregroundStyle(.appSecondaryText)
                        }
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .safeAreaInset(edge: .bottom) {
                doneBar
            }
            .navigationTitle("Voice capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        transcriber.cancel()
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        isEditorFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Hide keyboard")
                }
            }
            .navigationDestination(isPresented: $showReview) {
                CaptureReviewView(
                    suggestions: reviewSuggestions,
                    source: reviewSource,
                    itemSource: .app
                ) { summary in
                    onSaved(summary)
                    dismiss()
                }
            }
        }
        .tint(.appAccent)
        // Opening voice capture means "listen": start right away (asks for permission the first time).
        .task {
            await startListening()
        }
        .onDisappear {
            transcriber.cancel()
        }
        .onChange(of: scenePhase) { _, phase in
            // Never keep the microphone open in the background. (Not on `.inactive`:
            // the permission prompt makes the app inactive while it's starting.)
            if phase == .background {
                transcriber.stop()
            }
        }
        .onChange(of: transcriber.text) { _, newText in
            draft = newText
        }
    }

    // MARK: - Pieces

    private var isListening: Bool {
        transcriber.state == .listening
    }

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var micButton: some View {
        let diameter = min(micDiameter, 140)

        return Button {
            toggleListening()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(isListening ? 0.16 : 0.08))
                    .frame(width: diameter * 1.4, height: diameter * 1.4)
                    .scaleEffect(ringScale)

                Circle()
                    .fill(isListening ? Color.appAccent : Color.appSurface)
                    .frame(width: diameter, height: diameter)
                    .overlay(
                        Circle().stroke(.appHairline.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.06), radius: 10, x: 0, y: 4)

                Image(systemName: isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: diameter * 0.34, weight: .semibold))
                    .foregroundStyle(isListening ? Color.appBackground : Color.appAccent)
            }
            .frame(width: diameter * 1.5, height: diameter * 1.5)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(transcriber.state == .preparing || transcriber.state == .finishing || isSorting)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: transcriber.level)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isListening)
        .accessibilityLabel(isListening ? "Stop listening" : "Start listening")
        .accessibilityHint(isListening ? "Your words stay here." : "Turns on the microphone so you can talk.")
    }

    /// The soft ring follows your voice. With Reduce Motion it stays still.
    private var ringScale: CGFloat {
        guard !reduceMotion, isListening else { return 1 }
        return 1 + CGFloat(transcriber.level) * 0.18
    }

    private var statusText: String {
        switch transcriber.state {
        case .preparing:
            return "Getting ready…"
        case .listening:
            return "Listening…"
        case .finishing:
            return "Catching the last words…"
        case .idle:
            if transcriber.issue != nil {
                return "You can type here instead."
            }
            if let reason = transcriber.stopReason {
                return VoiceAutoStop.message(for: reason)
            }
            return isDraftEmpty
                ? "Tap the mic and say what’s on your mind."
                : "Tap the mic to add more, or Done when you’re ready."
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        if transcriber.isActive {
            // Live words, read-only while the mic is open.
            Text(draft.isEmpty ? " " : draft)
                .font(.title3)
                .foregroundStyle(.appPrimaryText)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
                .cardStyle()
                .accessibilityLabel(draft.isEmpty ? "Nothing yet" : draft)
        } else {
            CardTextEditor(
                placeholder: "Your words. You can type or fix them here.",
                text: $draft,
                icon: "text.quote",
                minHeight: 140
            )
            .focused($isEditorFocused)
        }
    }

    private func issueCard(_ issue: VoiceIssue) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.message)
                .font(.subheadline)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if issue.opensSettings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .cardStyle()
    }

    private var doneBar: some View {
        Button {
            Haptics.tap()
            Task { await sortItOut() }
        } label: {
            HStack(spacing: 8) {
                if isSorting {
                    ProgressView()
                }
                Text(isSorting ? "Sorting it out…" : "Done")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isDraftEmpty || isSorting || transcriber.state == .preparing)
        .accessibilityHint("Sorts your words into items you can check before saving.")
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }

    // MARK: - Actions

    private func toggleListening() {
        switch transcriber.state {
        case .listening:
            transcriber.stop()
        case .idle:
            Haptics.tap()
            Task { await startListening() }
        case .preparing, .finishing:
            break
        }
    }

    private func startListening() async {
        isEditorFocused = false
        await transcriber.start(continuing: draft)
    }

    /// Stops listening, asks AI (or the rules) to sort the words, and opens the review.
    private func sortItOut() async {
        guard !isSorting else { return }
        isEditorFocused = false
        isSorting = true

        let wasListening = transcriber.isActive
        await transcriber.finishListening()
        if wasListening {
            draft = transcriber.text
        }

        let words = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else {
            isSorting = false
            return
        }

        let profile = ProfileStore.activeProfile(in: context)
        let result = await AIService.capture(words, context: CaptureContext.current(profile: profile))
        if result.value.isEmpty {
            reviewSuggestions = CaptureSaver.rulesSuggestions(for: words, profile: profile)
            reviewSource = .rules
        } else {
            reviewSuggestions = result.value
            reviewSource = result.source
        }

        isSorting = false
        showReview = true
    }
}
