//
//  InboxView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI
import SwiftData

struct InboxView: View {
    @Environment(\.modelContext) private var context

    // NOTE: We query unsorted so we can apply dynamic ordering (manual sortIndex first, else createdAt).
    @Query private var items: [InboxItem]

    @AppStorage("inboxManualPrioritizationEnabled") private var manualPrioritizationEnabled: Bool = true
    @State private var isReorderMode = false
    @State private var orderedItems: [InboxItem] = []

    @State private var showQuickAdd = false
    @State private var itemPendingDeletion: InboxItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    if displayedItems.isEmpty {
                        emptyStateRow
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.appBackground)
                    } else {
                        ForEach(isReorderMode ? orderedItems : displayedItems) { item in
                            NavigationLink {
                                InboxDetailView(item: item)
                            } label: {
                                InboxRow(item: item)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.appBackground)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    Haptics.tap()
                                    itemPendingDeletion = item
                                } label: {
                                    Label("Not needed", systemImage: "trash")
                                }
                            }
                        }
                        .onMove(perform: handleMove)
                    }
                }
                .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))
                .environment(\.defaultMinListRowHeight, 44)
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.appBackground)
            }
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.appAccent)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if manualPrioritizationEnabled {
                        Button(isReorderMode ? "Done" : "Reorder") {
                            Haptics.tap()
                            if !isReorderMode {
                                ensureSortIndexesExist()
                                orderedItems = displayedItems
                            }
                            isReorderMode.toggle()
                        }
                        .accessibilityLabel(isReorderMode ? "Finish reordering inbox" : "Reorder inbox")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick add to inbox")
                    .disabled(isReorderMode) // optional: avoids weirdness while dragging
                }
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddView()
                    .presentationBackground(Color.appBackground)
            }
            .confirmationDialog(
                "Let this go?",
                isPresented: Binding(
                    get: { itemPendingDeletion != nil },
                    set: { if !$0 { itemPendingDeletion = nil } }
                ),
                presenting: itemPendingDeletion
            ) { item in
                Button("Let go", role: .destructive) {
                    delete(item)
                    itemPendingDeletion = nil
                }
                Button("Keep", role: .cancel) {
                    itemPendingDeletion = nil
                }
            } message: { _ in
                Text("You don’t have to do everything.")
            }
        }
    }

    // MARK: - Display ordering

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

    private func ensureSortIndexesExist() {
        // Assign indices only for items that don't have them yet.
        // This makes reordering stable the first time a user opts in.
        var didChange = false

        for (idx, item) in displayedItems.enumerated() {
            if item.sortIndex == nil {
                item.sortIndex = idx
                didChange = true
            }
        }

        guard didChange else { return }

        do {
            try context.save()
        } catch {
            print("❌ Save failed (ensureSortIndexesExist):", error)
        }
    }
    
    private func handleMove(from source: IndexSet, to destination: Int) {
        guard manualPrioritizationEnabled && isReorderMode else { return }
        moveItems(from: source, to: destination)
    }

    private func moveItems(from source: IndexSet, to destination: Int) {
        var reordered = orderedItems
        reordered.move(fromOffsets: source, toOffset: destination)
        orderedItems = reordered

        for (idx, item) in reordered.enumerated() {
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

    // MARK: - UI

    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inbox is empty")
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("Captured thoughts land here when there’s no time yet.")
                .foregroundStyle(.appSecondaryText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
    }

    // MARK: - Actions

    private func delete(_ item: InboxItem) {
        context.delete(item)

        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (delete):", error)
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.title)
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("Start: \(item.startStep) (\(item.estimateMinutes) min)")
                .foregroundStyle(.appSecondaryText)
                .lineLimit(2)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
        .padding(.vertical, 1)
    }
    
}
