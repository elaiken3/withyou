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
    @State private var text: String = ""
    private let parser = CaptureParser()

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Type or dictate… (e.g., “Email landlord tomorrow morning”)", text: $text, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Capture")
        }
    }

    private func save() {
        ProfileStore.ensureDefaultProfile(in: context)
        let profile = ProfileStore.activeProfile(in: context)

        // If focusing, route to Focus Dump
        if let active = FocusStore.activeSession(in: context),
           (profile?.routeSiriToFocusDumpWhenActive ?? true) {
            context.insert(FocusDumpItem(text: text, sessionId: active.id))
            try? context.save()
            text = ""
            return
        }

        let parsed = parser.parse(text, profile: profile)
        if let when = parsed.scheduledAt {
            let reminder = VerboseReminder(title: parsed.title, startStep: parsed.startStep, estimateMinutes: parsed.estimateMinutes, scheduledAt: when)
            context.insert(reminder)
            try? context.save()

            Task {
                let body = "Start: \(reminder.startStep) (\(reminder.estimateMinutes) min)\nTap “Help me start” if you’re stuck."
                try? await NotificationManager.shared.scheduleReminder(id: reminder.id, title: reminder.title, body: body, scheduledAt: reminder.scheduledAt)
            }
        } else {
            let inbox = InboxItem(content: text, title: parsed.title, source: .app, startStep: parsed.startStep, estimateMinutes: parsed.estimateMinutes)
            context.insert(inbox)
            try? context.save()
        }

        text = ""
    }
}

