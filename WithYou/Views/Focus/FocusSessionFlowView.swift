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

    enum Step { case setup, dump, running, review }

    var body: some View {
        NavigationStack {
            switch step {
            case .setup: setupView
            case .dump: dumpView
            case .running:
                if let s = session { FocusTimerView(session: s) { step = .review } }
            case .review:
                if let s = session { FocusReviewView(session: s) { step = .setup; session = nil } }
            }
        }
        .onAppear {
            ProfileStore.ensureDefaultProfile(in: context)
            if let p = ProfileStore.activeProfile(in: context) {
                durationSeconds = p.defaultFocusMinutes * 60
            }
        }
    }

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
            HStack {
                durationButton("25", 25*60)
                durationButton("45", 45*60)
                durationButton("60", 60*60)
            }

            Button("Continue") {
                startSession()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)
            .disabled(focusTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
    }

    private func durationButton(_ label: String, _ seconds: Int) -> some View {
        Button("\(label) min") { durationSeconds = seconds }
            .frame(maxWidth: .infinity)
            .buttonStyle(durationSeconds == seconds ? .borderedProminent : .bordered)
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
                    .buttonStyle(.borderedProminent)
                    .disabled(dumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let s = session {
                FocusDumpList(sessionId: s.id)
            }

            Button("Begin Focus") {
                session?.startedAt = Date()
                try? context.save()
                step = .running
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderedProminent)

            Text("You don’t need to remember these during this session.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding()
    }

    private func startSession() {
        // end existing active session (MVP)
        if let existing = FocusStore.activeSession(in: context) {
            existing.isActive = false
            existing.endedAt = Date()
        }

        let s = FocusSession(focusTitle: focusTitle, focusStartStep: focusStartStep, durationSeconds: durationSeconds, isActive: true)
        context.insert(s)
        try? context.save()
        session = s
        step = .dump
    }

    private func addDumpItem() {
        guard let s = session else { return }
        let trimmed = dumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(FocusDumpItem(text: trimmed, sessionId: s.id))
        try? context.save()
        dumpText = ""
    }
}

private struct FocusDumpList: View {
    let sessionId: UUID
    @Query private var items: [FocusDumpItem]
    @Environment(\.modelContext) private var context

    init(sessionId: UUID) {
        self.sessionId = sessionId
        _items = Query(filter: #Predicate<FocusDumpItem> { $0.sessionId == sessionId },
                       sort: [SortDescriptor(\.createdAt, order: .reverse)])
    }

    var body: some View {
        List {
            ForEach(items) { item in
                Text(item.text)
            }
            .onDelete { idx in
                for i in idx { context.delete(items[i]) }
                try? context.save()
            }
        }
        .frame(minHeight: 140)
    }
}
