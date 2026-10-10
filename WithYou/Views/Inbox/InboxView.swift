//
//  InboxView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import Foundation
import SwiftUI
import SwiftData

/// The mental parking lot. Nothing here is overdue and nothing nags.
struct InboxView: View {
    @Environment(\.modelContext) private var context

    @Query private var items: [InboxItem]

    @AppStorage("inboxManualPrioritizationEnabled") private var manualPrioritizationEnabled: Bool = true
    @State private var editMode: EditMode = .inactive
    @State private var orderedItems: [InboxItem] = []

    @State private var showQuickAdd = false
    @State private var itemToSchedule: InboxItem?
    @State private var toast: Toast?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if currentItems.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .tint(.appAccent)
            .sheet(isPresented: $showQuickAdd) {
                QuickAddView(showsCloseButton: true)
                    .presentationBackground(Color.appBackground)
            }
            .sheet(item: $itemToSchedule) { item in
                ScheduleSheetV2(
                    title: item.title,
                    startStep: item.startStep,
                    estimate: item.estimateMinutes
                ) { date in
                    schedule(item, at: date)
                }
                .presentationBackground(Color.appBackground)
            }
            .toast($toast)
            // Another screen needs its sheet up (see `AppRouter.closeAllSheets()`).
            .onChange(of: AppRouter.shared.closeSheetsRequest) { _, _ in
                showQuickAdd = false
                itemToSchedule = nil
            }
        }
    }

    // MARK: - List

    private var listContent: some View {
        List {
            ForEach(currentItems, id: \.id) { item in
                rowContent(for: item)
            }
            .onMove { from, to in
                if isReorderMode {
                    handleMove(from: from, to: to)
                }
            }
        }
        .environment(\.editMode, $editMode)
        .environment(\.defaultMinListRowHeight, 44)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.appBackground)
    }

    // MARK: - Row content (extracted for type-checker)

    @ViewBuilder
    private func rowContent(for item: InboxItem) -> some View {
        if isReorderMode {
            InboxRow(item: item)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.appBackground)
        } else {
            NavigationLink {
                InboxDetailView(item: item)
            } label: {
                InboxRow(item: item)
            }
            .listRowSeparator(.hidden)
            .listRowBackground(Color.appBackground)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    Haptics.tap()
                    itemToSchedule = item
                } label: {
                    Label("Schedule", systemImage: "calendar")
                }
                .tint(.appAccent)

                Button {
                    complete(item)
                } label: {
                    Label("Done", systemImage: "checkmark")
                }
                .tint(.appAccent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button {
                    letGo(item)
                } label: {
                    Label("Let go", systemImage: "leaf")
                }
                .tint(.appSecondaryText)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            reorderButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            addButton
        }
    }

    @ViewBuilder
    private var reorderButton: some View {
        // Reordering only means something with two or more items.
        if manualPrioritizationEnabled && (isReorderMode || items.count > 1) {
            Button(isReorderMode ? "Done" : "Reorder") {
                Haptics.tap()
                if !isReorderMode {
                    orderedItems = displayedItems
                    editMode = .active
                } else {
                    persistCurrentOrder()
                    editMode = .inactive
                }
            }
            .accessibilityLabel(isReorderMode ? "Finish reordering inbox" : "Reorder inbox")
        }
    }

    private var addButton: some View {
        Button {
            Haptics.tap()
            showQuickAdd = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add to Inbox")
        .disabled(isReorderMode)
    }

    // MARK: - Display ordering

    private var currentItems: [InboxItem] {
        isReorderMode ? orderedItems : displayedItems
    }

    private var displayedItems: [InboxItem] {
        if manualPrioritizationEnabled {
            return items.sorted { a, b in
                switch (a.sortIndex, b.sortIndex) {
                case let (ai?, bi?): return ai < bi
                case (_?, nil):     return true
                case (nil, _?):     return false
                case (nil, nil):    return a.createdAt > b.createdAt
                }
            }
        } else {
            return items.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private func handleMove(from source: IndexSet, to destination: Int) {
        guard manualPrioritizationEnabled && isReorderMode else { return }
        orderedItems.move(fromOffsets: source, toOffset: destination)
    }

    private func persistCurrentOrder() {
        for (idx, item) in orderedItems.enumerated() {
            item.sortIndex = idx
        }

        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (reorder):", error)
        }
    }

    private var isReorderMode: Bool {
        editMode == .active
    }

    // MARK: - Empty state

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.largeTitle)
                        .foregroundStyle(.appSecondaryText)
                        .accessibilityHidden(true)

                    Text("Nothing parked here.")
                        .font(.headline)
                        .foregroundStyle(.appPrimaryText)

                    Text("Captured thoughts without a time land here — no rush to sort them.")
                        .font(.subheadline)
                        .foregroundStyle(.appSecondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                Button {
                    Haptics.tap()
                    showQuickAdd = true
                } label: {
                    Label("Add a thought", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .tint(.appAccent)
                .disabled(isReorderMode)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 72)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: - Actions

    /// Lets the item go right away, with Undo, instead of asking first. Fewer decisions.
    private func letGo(_ item: InboxItem) {
        Haptics.tap()

        // Keep everything needed to put it back exactly where it was.
        let content = item.content
        let title = item.title
        let createdAt = item.createdAt
        let source = item.source
        let startStep = item.startStep
        let estimate = item.estimateMinutes
        let sortIndex = item.sortIndex

        context.delete(item)
        do {
            try context.save()
        } catch {
            Haptics.error()
            print("❌ Save failed (let go):", error)
            return
        }

        toast = Toast(text: "Let go.", actionTitle: "Undo", action: {
            let restored = InboxItem(
                content: content,
                title: title,
                createdAt: createdAt,
                source: source,
                startStep: startStep,
                estimateMinutes: estimate,
                sortIndex: sortIndex
            )
            context.insert(restored)
            do {
                try context.save()
            } catch {
                print("❌ Save failed (undo let go):", error)
            }
        })
    }

    private func complete(_ item: InboxItem) {
        CompletionStore.completeInboxItem(item, in: context)
        Haptics.success()
        toast = Toast(text: "Nice. That counted.")
    }

    /// Turns the item into a reminder; it leaves the Inbox once the reminder is saved.
    private func schedule(_ item: InboxItem, at date: Date) {
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
                print("❌ Save failed (schedule from Inbox):", error)
                toast = Toast(text: "Couldn’t schedule that just now. It’s still here.")
                return
            }

            // The reminder is saved, so the parked thought can leave the Inbox.
            context.delete(item)
            do {
                try context.save()
            } catch {
                print("❌ Save failed (remove scheduled item):", error)
            }
            Haptics.success()
            toast = Toast(text: "Scheduled for \(date.friendlyDayTime).")
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    private var startStep: String {
        item.startStep.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            if !startStep.isEmpty {
                Text("Start: \(startStep) (\(item.estimateMinutes) min)")
                    .font(.subheadline)
                    .foregroundStyle(.appSecondaryText)
                    .lineLimit(3)
            }
        }
        .cardStyle(padding: 12)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
