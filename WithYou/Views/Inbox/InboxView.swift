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
    @Query(sort: \InboxItem.createdAt, order: .reverse) private var items: [InboxItem]

    @State private var showQuickAdd = false
    @State private var itemPendingDeletion: InboxItem?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    if items.isEmpty {
                        emptyStateRow
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.appBackground)
                    } else {
                        ForEach(items) { item in
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
                }
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
                    Button {
                        Haptics.tap()
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick add to inbox")
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
