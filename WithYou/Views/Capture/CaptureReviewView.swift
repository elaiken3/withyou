//
//  CaptureReviewView.swift
//  WithYou
//
//  A look over what WithYou made of a capture before anything is saved.
//  AI (or the simple rules) only suggests; the person edits, unchecks, then saves.
//

import Foundation
import SwiftUI
import SwiftData

/// What to review: the suggestions and where they came from.
struct CaptureReviewRequest: Identifiable {
    let id = UUID()
    var suggestions: [CaptureSuggestion]
    var source: AISource
}

/// One row as the person edits it.
struct CaptureReviewRow: Identifiable, Equatable {
    var suggestion: CaptureSuggestion
    var isIncluded = true
    /// The time that was first suggested, so "Inbox instead" can be changed back.
    let suggestedDate: Date?

    var id: UUID { suggestion.id }

    init(_ suggestion: CaptureSuggestion) {
        self.suggestion = suggestion
        self.suggestedDate = suggestion.scheduledAt
    }
}

/// Words for the review screen, kept together so they stay consistent (and testable).
enum CaptureReviewText {
    static func saveTitle(count: Int) -> String {
        count > 1 ? "Save \(count)" : "Save"
    }

    static func saveAccessibilityLabel(count: Int) -> String {
        count == 1 ? "Save 1 item" : "Save \(count) items"
    }

    /// Small, quiet attribution, worded like every other AI suggestion. Nothing for the simple rules.
    static func attribution(for source: AISource) -> String? {
        AIAttribution.text(for: source)
    }

    static func destination(for date: Date?) -> String {
        guard let date else { return "→ Inbox" }
        return "→ \(date.friendlyDayTime)"
    }

    static func spokenDestination(for date: Date?) -> String {
        guard let date else { return "Goes to your Inbox" }
        return "Scheduled for \(date.friendlyDayTime)"
    }

    static func header(count: Int) -> String {
        count == 1
            ? "Here’s how I’d save it. Change anything you like."
            : "Here’s how I’d sort it. Change anything you like, and uncheck anything you don’t need."
    }
}

struct CaptureReviewView: View {
    @Environment(\.modelContext) private var context

    let source: AISource
    let itemSource: ItemSource
    /// When set, a "Close" button is shown (the review is the first screen of its sheet).
    let onClose: (() -> Void)?
    /// Called after saving with what was created, so the presenter can close and show a toast.
    let onSaved: (CaptureSaveSummary) -> Void

    @State private var rows: [CaptureReviewRow]
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        suggestions: [CaptureSuggestion],
        source: AISource,
        itemSource: ItemSource = .app,
        onClose: (() -> Void)? = nil,
        onSaved: @escaping (CaptureSaveSummary) -> Void
    ) {
        self.source = source
        self.itemSource = itemSource
        self.onClose = onClose
        self.onSaved = onSaved
        _rows = State(initialValue: suggestions.map { CaptureReviewRow($0) })
    }

    private var includedCount: Int {
        rows.filter { $0.isIncluded }.count
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    ForEach($rows) { $row in
                        CaptureReviewRowView(row: $row)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.appSecondaryText)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        onClose()
                    }
                }
            }
        }
        .tint(.appAccent)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(CaptureReviewText.header(count: rows.count))
                .font(.subheadline)
                .foregroundStyle(.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if let attribution = CaptureReviewText.attribution(for: source) {
                Label(attribution, systemImage: AIAttribution.systemImage(for: source))
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
            }
        }
        .padding(.bottom, 4)
    }

    private var saveBar: some View {
        Button {
            Task { await save() }
        } label: {
            HStack(spacing: 8) {
                if isSaving {
                    ProgressView()
                }
                Text(CaptureReviewText.saveTitle(count: includedCount))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isSaving || includedCount == 0)
        .accessibilityLabel(CaptureReviewText.saveAccessibilityLabel(count: includedCount))
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }

    // MARK: - Saving

    private func save() async {
        guard !isSaving else { return }
        let chosen = rows.filter { $0.isIncluded }.map { $0.suggestion }
        guard !chosen.isEmpty else { return }

        Haptics.tap()
        isSaving = true
        errorMessage = nil
        do {
            let summary = try await CaptureSaver.save(chosen, source: itemSource, in: context)
            Haptics.success()
            isSaving = false
            onSaved(summary)
        } catch {
            print("❌ Save failed (capture review):", error)
            Haptics.error()
            errorMessage = "Couldn’t save that just now. Try again."
            isSaving = false
        }
    }
}

// MARK: - Row

private struct CaptureReviewRowView: View {
    @Binding var row: CaptureReviewRow

    private enum Field {
        case title
        case firstStep
    }

    @FocusState private var focusedField: Field?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            includeButton

            VStack(alignment: .leading, spacing: 8) {
                TextField("What is it?", text: $row.suggestion.title, axis: .vertical)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.appPrimaryText)
                    .submitLabel(.done)
                    .focused($focusedField, equals: .title)
                    .accessibilityLabel("Title")

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "arrow.right.circle")
                        .font(.subheadline)
                        .foregroundStyle(.appSecondaryText)
                        .accessibilityHidden(true)
                    TextField("First step (optional)", text: $row.suggestion.firstStep, axis: .vertical)
                        .font(.subheadline)
                        .foregroundStyle(.appSecondaryText)
                        .submitLabel(.done)
                        .focused($focusedField, equals: .firstStep)
                        .accessibilityLabel("First step")
                }

                destination
            }
            .padding(.top, 10)
        }
        .cardStyle(padding: 10)
        .opacity(row.isIncluded ? 1 : 0.6)
        // These fields wrap, so Return would add a new line. Treat it as "done" instead.
        .onChange(of: row.suggestion.title) { _, newValue in
            if let cleaned = Self.withoutReturn(newValue) {
                row.suggestion.title = cleaned
                focusedField = nil
            }
        }
        .onChange(of: row.suggestion.firstStep) { _, newValue in
            if let cleaned = Self.withoutReturn(newValue) {
                row.suggestion.firstStep = cleaned
                focusedField = nil
            }
        }
    }

    /// `text` without line breaks, or nil when it had none.
    private static func withoutReturn(_ text: String) -> String? {
        guard text.contains("\n") else { return nil }
        return text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    /// Looks like a check circle; VoiceOver hears a real toggle.
    private var includeButton: some View {
        Button {
            Haptics.tap()
            row.isIncluded.toggle()
        } label: {
            Image(systemName: row.isIncluded ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(row.isIncluded ? Color.appAccent : Color.appSecondaryText)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn: $row.isIncluded) {
                Text("Include \(row.suggestion.title)")
            }
        }
    }

    @ViewBuilder
    private var destination: some View {
        if row.suggestion.scheduledAt != nil {
            Menu {
                Button("Put it in the Inbox instead") {
                    row.suggestion.scheduledAt = nil
                }
            } label: {
                destinationChip(changeable: true)
            }
        } else if let suggested = row.suggestedDate {
            Menu {
                Button("Schedule for \(suggested.friendlyDayTime)") {
                    row.suggestion.scheduledAt = suggested
                }
            } label: {
                destinationChip(changeable: true)
            }
        } else {
            destinationChip(changeable: false)
        }
    }

    private func destinationChip(changeable: Bool) -> some View {
        HStack(spacing: 4) {
            Text(CaptureReviewText.destination(for: row.suggestion.scheduledAt))
            if changeable {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .accessibilityHidden(true)
            }
        }
        .font(.footnote)
        .foregroundStyle(.appSecondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(.appBackground)
        )
        .overlay(
            Capsule().stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .frame(minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CaptureReviewText.spokenDestination(for: row.suggestion.scheduledAt))
    }
}
