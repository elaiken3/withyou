//
//  FocusReviewView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct FocusReviewView: View {
    @Environment(\.modelContext) private var context
    let session: FocusSession
    /// True only when the person chose "I finished it".
    let completed: Bool
    var onDone: () -> Void

    @Query private var dumpItems: [FocusDumpItem]
    @State private var toast: Toast?
    /// Thoughts being scheduled right now (the reminder is created asynchronously).
    @State private var schedulingIds: Set<UUID> = []

    private let parser = CaptureParser()

    init(session: FocusSession, completed: Bool, onDone: @escaping () -> Void) {
        self.session = session
        self.completed = completed
        self.onDone = onDone
        let id: UUID = session.id
        _dumpItems = Query(
            filter: #Predicate<FocusDumpItem> { (item: FocusDumpItem) in
                item.sessionId == id
            },
            sort: [SortDescriptor<FocusDumpItem>(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if dumpItems.isEmpty {
                        Text("Nothing parked this time. You’re all set.")
                            .foregroundStyle(.appSecondaryText)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            SectionHeader(title: "Thoughts you parked")
                            Text("Decide now, or leave them for later.")
                                .font(.subheadline)
                                .foregroundStyle(.appSecondaryText)
                        }

                        LazyVStack(spacing: 12) {
                            ForEach(dumpItems) { item in
                                thoughtRow(item)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        if !dumpItems.isEmpty {
                            Text("Anything left here moves to your Inbox.")
                                .font(.footnote)
                                .foregroundStyle(.appSecondaryText)
                        }

                        Button {
                            Haptics.tap()
                            returnToToday()
                        } label: {
                            Text("Return to Today")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.appAccent)
                        .disabled(!schedulingIds.isEmpty)
                    }
                    .padding(.top, 8)

                    Spacer(minLength: 24)
                }
                .padding()
            }
        }
        .navigationTitle("Wrap up")
        .tint(.appAccent)
        .toast($toast)
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(completed ? "Nice work." : "That counted.")
                .font(.largeTitle).bold()
                .foregroundStyle(.appPrimaryText)
                .accessibilityAddTraits(.isHeader)

            Text(subtitle)
                .foregroundStyle(.appSecondaryText)
        }
    }

    private var subtitle: String {
        if completed {
            return "“\(session.focusTitle)” is done."
        }
        return "Stopping is allowed. Your task is still where you left it."
    }

    private func thoughtRow(_ item: FocusDumpItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.text)
                .font(.body)
                .foregroundStyle(.appPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if schedulingIds.contains(item.id) {
                ProgressView()
                    .accessibilityLabel("Scheduling")
            } else {
                // Side by side when they fit; stacked (with icons) at larger text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        rowButtons(for: item)
                    }
                    .labelStyle(.titleOnly)

                    VStack(alignment: .leading, spacing: 8) {
                        rowButtons(for: item)
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func rowButtons(for item: FocusDumpItem) -> some View {
        Button {
            Haptics.tap()
            schedule(item)
        } label: {
            Label("Schedule", systemImage: "calendar")
        }
        .buttonStyle(.bordered)
        .tint(.appAccent)
        .accessibilityHint("Creates a gentle reminder")

        Button {
            Haptics.tap()
            sendToInbox(item)
        } label: {
            Label("Inbox", systemImage: "tray")
        }
        .buttonStyle(.bordered)
        .tint(.appAccent)
        .accessibilityLabel("Move to Inbox")

        Button {
            Haptics.tap()
            letGo(item)
        } label: {
            Label("Let it go", systemImage: "leaf")
        }
        .buttonStyle(.bordered)
        .tint(.appSecondaryText)
    }

    // MARK: - Actions

    private func returnToToday() {
        if completed {
            // Already done when "I finished it" was chosen; safe to repeat.
            CompletionStore.completeFromSession(session, in: context)
        } else if session.isActive {
            CompletionStore.endWithoutCompleting(session, in: context)
        }

        CompletionStore.moveLeftoverThoughtsToInbox(for: session, in: context)
        Haptics.success()
        onDone()
    }

    private func sendToInbox(_ item: FocusDumpItem) {
        CompletionStore.moveThoughtsToInbox([item], in: context)

        do {
            try context.save()
            Haptics.success()
            toast = Toast(text: "In your Inbox.")
        } catch {
            print("❌ Save failed (sendToInbox):", error)
        }
    }

    private func letGo(_ item: FocusDumpItem) {
        let text = item.text
        let sessionId = item.sessionId
        let createdAt = item.createdAt

        context.delete(item)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (letGo):", error)
            return
        }

        toast = Toast(text: "Let go.", actionTitle: "Undo", action: {
            context.insert(FocusDumpItem(text: text, sessionId: sessionId, createdAt: createdAt))
            try? context.save()
        })
    }

    private func schedule(_ item: FocusDumpItem) {
        let itemId = item.id
        guard !schedulingIds.contains(itemId) else { return }

        let profile = ProfileStore.activeProfile(in: context)
        let parsed = parser.parse(item.text, profile: profile)

        // Use a time mentioned in the thought ("call Sam at 4pm") if it is still ahead;
        // otherwise tomorrow morning.
        let when: Date
        if let mentioned = parsed.scheduledAt, mentioned > Date() {
            when = mentioned
        } else {
            when = ReminderStore.nextMorning(profile: profile)
        }

        schedulingIds.insert(itemId)

        Task {
            do {
                _ = try await ReminderStore.createAndSchedule(
                    title: parsed.title,
                    startStep: parsed.startStep,
                    estimateMinutes: parsed.estimateMinutes,
                    scheduledAt: when,
                    in: context
                )
                context.delete(item)
                try context.save()
                Haptics.success()
                toast = Toast(text: "Scheduled for \(when.friendlyDayTime).")
            } catch {
                print("❌ Save failed (schedule):", error)
                toast = Toast(text: "Couldn’t schedule that. It’s still here.")
            }
            schedulingIds.remove(itemId)
        }
    }
}
