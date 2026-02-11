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
    @State private var editMode: EditMode = .inactive
    @State private var orderedItems: [InboxItem] = []

    @State private var showQuickAdd = false
    @State private var itemPendingDeletion: InboxItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    if currentItems.isEmpty {
                        emptyStateRow
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.appBackground)
                    } else {
                        ForEach(currentItems, id: \.id) { item in
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        Haptics.tap()
                                        itemPendingDeletion = item
                                    } label: {
                                        Label("Not needed", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .onMove(perform: isReorderMode ? handleMove : nil)
                    }
                }
                .environment(\.editMode, $editMode)
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
                                // Snapshot the current display order before entering reorder mode
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick add to inbox")
                    .disabled(isReorderMode)
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
                Text("You don't have to do everything.")
            }
        }
    }

    // MARK: - Display ordering

    /// Which items to show: the mutable reorder snapshot when in edit mode,
    /// otherwise the computed display order from the query.
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

    // MARK: - UI

    private var emptyStateRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inbox is empty")
                .font(.headline)
                .foregroundStyle(.appPrimaryText)

            Text("Captured thoughts land here when there's no time yet.")
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