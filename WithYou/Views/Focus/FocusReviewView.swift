//
//  FocusReviewView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
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
    /// AI-tidied titles and first steps, by thought id. Used when a thought moves on;
    /// the original words stay in the Inbox item's `content`.
    @State private var tidied: [UUID: TidyItem] = [:]
    @State private var tidySource: AISource = .rules
    @State private var isTidying = false

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
                            tidyStatus
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
        // Tidies new thoughts in the background (again after an Undo brings one back).
        // Nothing waits on it: a thought that moves on before it's ready uses the parser.
        .task(id: dumpItems.map { $0.id }) {
            await tidyThoughts()
        }
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

    @ViewBuilder
    private var tidyStatus: some View {
        if isTidying {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Tidying titles…")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
            }
            .accessibilityElement(children: .combine)
        } else if !tidied.isEmpty {
            AIAttributionLabel(source: tidySource)
        }
    }

    private func thoughtRow(_ item: FocusDumpItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(item.text)
                .font(.body)
                .foregroundStyle(.appPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if let tidy = tidied[item.id] {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saves as “\(tidy.title)”")
                    Text("Start: \(tidy.firstStep)")
                }
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
            }

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

        CompletionStore.moveLeftoverThoughtsToInbox(for: session, tidied: tidied, in: context)
        Haptics.success()
        onDone()
    }

    /// Asks AI for a short title and first step for each thought not tidied yet. Only used
    /// when Apple Intelligence or cloud AI can help: the rules would just repeat the thought,
    /// and the parser already does better than that.
    private func tidyThoughts() async {
        let pending = dumpItems.filter { tidied[$0.id] == nil }
        guard !pending.isEmpty, AIService.isOnDeviceAvailable || AIService.isCloudEnabled else {
            isTidying = false
            return
        }

        isTidying = true
        let ids = pending.map { $0.id }
        let result = await AIService.tidy(pending.map { $0.text })
        // The thoughts changed or the screen closed; a newer run takes over.
        guard !Task.isCancelled else { return }
        isTidying = false

        guard result.source != .rules, result.value.count == ids.count else { return }
        for (id, item) in zip(ids, result.value) {
            tidied[id] = item
        }
        tidySource = result.source
    }

    private func sendToInbox(_ item: FocusDumpItem) {
        CompletionStore.moveThoughtsToInbox([item], tidied: tidied, in: context)

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
        let fields = CompletionStore.inboxFields(parsed: parsed, tidy: tidied[itemId])

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
                    title: fields.title,
                    startStep: fields.startStep,
                    estimateMinutes: fields.estimateMinutes,
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
