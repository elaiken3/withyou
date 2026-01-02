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
            List {
                if items.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Inbox is empty")
                            .font(.headline)

                        Text("Captured thoughts land here when there’s no time yet.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(items) { item in
                        NavigationLink {
                            InboxDetailView(item: item)
                        } label: {
                            InboxRow(item: item)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                itemPendingDeletion = item
                            } label: {
                                Label("Not needed", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQuickAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Quick add to inbox")
                }
            }
            .sheet(isPresented: $showQuickAdd) {
                QuickAddView()
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

    private func delete(_ item: InboxItem) {
        context.delete(item)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (delete):", error)
        }
    }
}

private struct InboxRow: View {
    let item: InboxItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.headline)

            Text("Start: \(item.startStep) (\(item.estimateMinutes) min)")
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }
}
