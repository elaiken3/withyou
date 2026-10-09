//
//  InboxDetailView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/25/25.
//

import Foundation
import SwiftUI
import SwiftData

struct InboxDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: InboxItem

    @State private var showSchedule = false
    @State private var showEdit = false
    @State private var confirmLetGo = false
    @State private var isLeaving = false
    /// Set just before the item is deleted, so the body never reads a deleted model
    /// while the screen pops back to the Inbox.
    @State private var isGone = false
    @State private var isMakingSmaller = false
    @State private var toast: Toast?

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            if !isGone {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        summaryCard

                        if let original = originalText {
                            originalCard(original)
                        }

                        actions
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Inbox item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    Haptics.tap()
                    showEdit = true
                }
                .disabled(isLeaving)
            }
        }
        .tint(.appAccent)
        .toast($toast)
        .sheet(isPresented: $showSchedule) {
            ScheduleSheetV2(
                title: item.title,
                startStep: item.startStep,
                estimate: item.estimateMinutes
            ) { date in
                schedule(date: date)
            }
            .presentationBackground(Color.appBackground)
        }
        .sheet(isPresented: $showEdit) {
            EditInboxItemSheet(item: item)
                .presentationBackground(Color.appBackground)
        }
        .confirmationDialog(
            "Let this go?",
            isPresented: $confirmLetGo,
            titleVisibility: .visible
        ) {
            Button("Let it go") {
                letGo()
            }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("You don’t have to do everything.")
        }
    }

    // MARK: - Content

    private var startStep: String {
        item.startStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// What the person originally typed or said, when parsing turned it into a different title.
    private var originalText: String? {
        let original = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty, original.caseInsensitiveCompare(title) != .orderedSame else { return nil }
        return original
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !startStep.isEmpty {
                Text("Start: \(startStep) (\(item.estimateMinutes) min)")
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func originalCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("You wrote")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.appSecondaryText)
                .accessibilityAddTraits(.isHeader)

            Text(text)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .cardStyle()
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                Haptics.tap()
                showSchedule = true
            } label: {
                Label("Schedule", systemImage: "calendar.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                makeSmaller()
            } label: {
                HStack(spacing: 8) {
                    if isMakingSmaller {
                        ProgressView()
                    } else {
                        Image(systemName: "scissors")
                            .accessibilityHidden(true)
                    }
                    Text(isMakingSmaller ? "Finding a smaller step…" : "Make it smaller")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isMakingSmaller)
            .accessibilityHint("Suggests a tinier first step")

            Button {
                complete()
            } label: {
                Label("Mark completed", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                Haptics.tap()
                confirmLetGo = true
            } label: {
                Label("Let it go", systemImage: "leaf")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.appSecondaryText)
        }
        .controlSize(.large)
        .disabled(isLeaving)
    }

    // MARK: - Actions

    private func makeSmaller() {
        guard !isMakingSmaller else { return }
        Haptics.tap()
        isMakingSmaller = true

        let itemId = item.id
        let title = item.title
        let previousStep = item.startStep
        let previousEstimate = item.estimateMinutes

        Task {
            let step = await SmallStepSuggester.smallerStep(for: title, current: previousStep)
            isMakingSmaller = false

            // The item may have been let go elsewhere while the suggestion was coming.
            guard let current = fetchItem(id: itemId) else { return }
            current.startStep = step
            current.estimateMinutes = max(1, min(previousEstimate, 2))

            do {
                try context.save()
                Haptics.success()
                toast = Toast(text: "Smaller first step saved.", actionTitle: "Undo", action: {
                    guard let again = fetchItem(id: itemId) else { return }
                    again.startStep = previousStep
                    again.estimateMinutes = previousEstimate
                    try? context.save()
                })
            } catch {
                Haptics.error()
                print("❌ Save failed (makeSmaller):", error)
                toast = Toast(text: "Couldn’t save that just now.")
            }
        }
    }

    private func fetchItem(id: UUID) -> InboxItem? {
        var descriptor = FetchDescriptor<InboxItem>(
            predicate: #Predicate<InboxItem> { (candidate: InboxItem) in
                candidate.id == id
            }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func complete() {
        guard !isLeaving else { return }
        isLeaving = true
        isGone = true
        CompletionStore.completeInboxItem(item, in: context)
        Haptics.success()
        dismiss()
    }

    private func letGo() {
        guard !isLeaving else { return }
        isLeaving = true
        isGone = true

        context.delete(item)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (let go):", error)
        }
        dismiss() // back to the Inbox right away so it simply disappears
    }

    private func schedule(date: Date) {
        guard !isLeaving else { return }
        isLeaving = true

        let title = item.title
        let startStep = item.startStep
        let estimate = item.estimateMinutes

        Task {
            do {
                _ = try await ReminderStore.createAndSchedule(
                    title: title,
                    startStep: startStep,
                    estimateMinutes: estimate,
                    scheduledAt: date,
                    in: context
                )
            } catch {
                Haptics.error()
                print("❌ Save failed (schedule):", error)
                isLeaving = false
                toast = Toast(text: "Couldn’t schedule that just now. It’s still here.")
                return
            }

            // The reminder is saved; scheduled items leave the Inbox.
            isGone = true
            context.delete(item)
            do {
                try context.save()
            } catch {
                print("❌ Save failed (remove scheduled item):", error)
            }
            Haptics.success()
            dismiss()
        }
    }
}
