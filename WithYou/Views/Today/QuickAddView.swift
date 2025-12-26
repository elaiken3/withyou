//
//  QuickAddView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct QuickAddView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var isSaving = false
    @State private var lastErrorMessage: String?

    private let parser = CaptureParser()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {

                TextField("Type or dictate… (e.g., “Email landlord tomorrow morning”)", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.top)

                if let msg = lastErrorMessage {
                    Text(msg)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                HStack(spacing: 12) {
                    Button {
                        save(mode: .smart)
                    } label: {
                        Text("Save")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaveDisabled)

                    Button {
                        save(mode: .inboxOnly)
                    } label: {
                        Text("Inbox only")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSaveDisabled)
                }
                .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        isSaving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum SaveMode {
        case smart       // schedule if time detected
        case inboxOnly   // never schedule
    }

    private func save(mode: SaveMode) {
        guard !isSaving else { return }
        isSaving = true
        lastErrorMessage = nil

        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        // If focusing, route to Focus Dump
        if let active = FocusSessionStore.activeSession(in: context),
           (profile?.routeSiriToFocusDumpWhenActive ?? true) {

            context.insert(FocusDumpItem(text: text, sessionId: active.id))
            do {
                try context.save()
                text = ""
                dismiss() // closes if presented as sheet
            } catch {
                lastErrorMessage = "Couldn’t save. Try again."
                print("❌ Save failed (FocusDump):", error)
            }
            isSaving = false
            return
        }

        // Parse input
        // If your CaptureParser requires 'now:', use the now version below.
        // let parsed = parser.parse(text, profile: profile, now: .now)
        let parsed = parser.parse(text, profile: profile)

        // Inbox-only mode: always create InboxItem
        if mode == .inboxOnly {
            let inbox = InboxItem(
                content: text,
                title: parsed.title,
                source: .app,
                startStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes
            )
            context.insert(inbox)

            do {
                try context.save()
                text = ""
                dismiss()
            } catch {
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
                startStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes,
                scheduledAt: when
            )
            context.insert(reminder)

            do {
                try context.save()
            } catch {
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
                    // Not fatal; reminder still exists in SwiftData.
                    print("❌ Notification schedule failed:", error)
                }
            }

            text = ""
            dismiss()
        } else {
            let inbox = InboxItem(
                content: text,
                title: parsed.title,
                source: .app,
                startStep: parsed.startStep,
                estimateMinutes: parsed.estimateMinutes
            )
            context.insert(inbox)

            do {
                try context.save()
                text = ""
                dismiss()
            } catch {
                lastErrorMessage = "Couldn’t save to Inbox. Try again."
                print("❌ Save failed (Inbox):", error)
            }
        }

        isSaving = false
    }
}
