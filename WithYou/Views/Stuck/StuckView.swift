//
//  StuckView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/31/25.
//

import SwiftUI
import SwiftData

struct StuckView: View {
    @Environment(\.modelContext) private var context
    @Binding var selectedTab: AppTab
    @Environment(\.dismiss) private var dismiss

    // Data sources
    let focusSessions: [FocusSession]
    let reminders: [VerboseReminder]
    let inboxItems: [InboxItem]

    @State private var suggestions: [StuckSuggestion] = []
    @State private var index: Int = 0
    @State private var startStepOverride: String? = nil

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("I’m stuck")
                    .font(.largeTitle)
                    .bold()

                Text("Let’s do one tiny thing.")
                    .foregroundStyle(.secondary)

                if current == nil {
                    Text("Nothing to choose right now. You’re okay.")
                        .foregroundStyle(.secondary)
                    Spacer()
                } else if let s = current {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(s.title)
                            .font(.title3)
                            .bold()

                        Text("Start: \(displayStartStep)")
                            .foregroundStyle(.secondary)

                        Text("Just 2 minutes. We’re only starting.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack {
                            Button("Start 2 minutes") { startTwoMinuteFocus(from: s) }
                                .buttonStyle(.borderedProminent)

                            Button("Make it smaller") { makeSmaller() }
                                .buttonStyle(.bordered)
                        }

                        HStack {
                            Button("Try a different one") { nextSuggestion() }
                                .buttonStyle(.bordered)

                            Button("Not now") { dismiss() }
                                .buttonStyle(.bordered)
                        }
                        .padding(.top, 2)
                    }
                    .padding(14)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    Spacer()
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                suggestions = StuckChooser.suggestions(
                    focusSessions: focusSessions,
                    reminders: reminders,
                    inboxItems: inboxItems
                )
                index = 0
                startStepOverride = nil
            }
        }
    }

    private var current: StuckSuggestion? {
        guard !suggestions.isEmpty, index >= 0, index < suggestions.count else { return nil }
        return suggestions[index]
    }

    private var displayStartStep: String {
        if let override = startStepOverride, !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return override
        }
        return current?.startStep ?? "Open what you need and do the smallest possible step for 2 minutes."
    }

    private func nextSuggestion() {
        guard !suggestions.isEmpty else { return }
        index = (index + 1) % suggestions.count
        startStepOverride = nil
    }

    private func makeSmaller() {
        startStepOverride = StuckChooser.makeEvenSmaller(displayStartStep)
    }

    private func startTwoMinuteFocus(from suggestion: StuckSuggestion) {
        // If they already have an active focus session suggestion, just jump to Focus.
        if suggestion.source == .activeFocus {
            selectedTab = .focus
            dismiss()
            return
        }

        // End any existing active session (safety)
        if let existing = FocusSessionStore.activeSession(in: context) {
            existing.isActive = false
            existing.endedAt = Date()
        }

        let session = FocusSession(
            focusTitle: suggestion.title,
            focusStartStep: displayStartStep,
            durationSeconds: 2 * 60,
            createdAt: Date(),
            startedAt: Date(),
            endedAt: nil,
            isActive: true
        )

        context.insert(session)

        do {
            try context.save()
            selectedTab = .focus
            dismiss()
        } catch {
            print("❌ Save failed (startTwoMinuteFocus):", error)
        }
    }
}
