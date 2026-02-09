//
//  QuickAddView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData
import UIKit

struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isTextFocused: Bool
    @FocusState private var isFirstStepFocused: Bool

    @State private var text: String = ""
    @State private var startStepText: String = ""
    @State private var showFirstStep: Bool = false

    @State private var isSaving = false
    @State private var lastErrorMessage: String?

    private let parser = CaptureParser()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 12) {

                    // Main capture input (multi-line)
                    CardTextEditor(
                        placeholder: "Type or dictate… (e.g., “Email landlord tomorrow morning”)",
                        text: $text,
                        icon: "sparkles",
                        minHeight: 120
                    )
                    .padding(.horizontal)
                    .padding(.top)
                    .focused($isTextFocused)

                    // Optional First Step (collapsed by default)
                    Button {
                        withAnimation(.easeInOut) { showFirstStep.toggle() }
                        if showFirstStep {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isFirstStepFocused = true
                            }
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isTextFocused = true
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(showFirstStep ? "Hide first step" : "Add a first step (optional)")
                                .foregroundStyle(.appPrimaryText)
                            Spacer()
                            Image(systemName: showFirstStep ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.appSecondaryText)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    if showFirstStep {
                        // First step (multi-line, but smaller)
                        CardTextEditor(
                            placeholder: "First step (e.g., Open the doc)",
                            text: $startStepText,
                            icon: "arrow.right.circle",
                            minHeight: 80
                        )
                        .padding(.horizontal)
                        .focused($isFirstStepFocused)
                    }

                    if let msg = lastErrorMessage {
                        Text(msg)
                            .foregroundStyle(.red)
                            .font(.footnote)
                            .padding(.horizontal)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Haptics.tap()
                            save(mode: .smart)
                        } label: {
                            Text("Save")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSaveDisabled)

                        Button {
                            Haptics.tap()
                            save(mode: .inboxOnly)
                        } label: {
                            Text("Inbox only")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSaveDisabled)
                    }
                    .padding(.horizontal)
                    .tint(.appAccent)

                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                isTextFocused = false
                isFirstStepFocused = false
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        Haptics.tap()
                        resetStateAndDismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        dismiss() }
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
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isTextFocused = true
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum SaveMode {
        case smart
        case inboxOnly
    }

    private func resolvedStartStep(parsedStartStep: String) -> String {
        let explicit = startStepText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        return parsedStartStep
    }

    private func resetStateAndDismiss() {
        text = ""
        startStepText = ""
        showFirstStep = false
        lastErrorMessage = nil

        isTextFocused = false
        isFirstStepFocused = false

        dismiss()
    }

    private func save(mode: SaveMode) {
        guard !isSaving else { return }
        isSaving = true
        lastErrorMessage = nil

        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedStep = startStepText.trimmingCharacters(in: .whitespacesAndNewlines)

        // If focusing, route to Focus Dump
        if let active = FocusSessionStore.activeSession(in: context),
           (profile?.routeSiriToFocusDumpWhenActive ?? true) {

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

            context.insert(FocusDumpItem(text: payload, sessionId: active.id))
            do {
                try context.save()
                Haptics.success()
                resetStateAndDismiss()
            } catch {
                Haptics.error()
                lastErrorMessage = "Couldn’t save. Try again."
                print("❌ Save failed (FocusDump):", error)
            }
            isSaving = false
            return
        }

        // Parse input
        let parsed = parser.parse(trimmedText, profile: profile)
        let startStepToUse = resolvedStartStep(parsedStartStep: parsed.startStep)

        // Inbox-only mode
        if mode == .inboxOnly {
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
                Haptics.success()
                resetStateAndDismiss()
            } catch {
                Haptics.error()
                lastErrorMessage = "Couldn’t save to Inbox. Try again."
                print("❌ Save failed (InboxOnly):", error)
            }

            isSaving = false
            return
        }

        // Smart mode: schedule if time detected
        if let when = parsed.scheduledAt {
            let reminder = VerboseReminder(
                title: parsed.title,
                startStep: startStepToUse,
                estimateMinutes: parsed.estimateMinutes,
                scheduledAt: when
            )
            context.insert(reminder)

            do {
                try context.save()
                Haptics.success()
            } catch {
                Haptics.error()
                lastErrorMessage = "Couldn’t schedule. Try again."
                print("❌ Save failed (Reminder):", error)
                isSaving = false
                return
            }

            Task {
                let body =
                """
                Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)
                Tap “Help me start” if you’re stuck.
                """

                do {
                    try await NotificationManager.shared.scheduleReminder(
                        id: reminder.id,
                        title: reminder.title,
                        body: body,
                        scheduledAt: reminder.scheduledAt
                    )
                } catch {
                    print("❌ Notification schedule failed:", error)
                }
            }

            resetStateAndDismiss()
        } else {
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
                Haptics.success()
                resetStateAndDismiss()
            } catch {
                Haptics.error()
                lastErrorMessage = "Couldn’t save to Inbox. Try again."
                print("❌ Save failed (Inbox):", error)
            }
        }

        isSaving = false
    }
}
