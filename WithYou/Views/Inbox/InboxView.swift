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
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
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
        }
    }

    private func delete(_ item: InboxItem) {
        context.delete(item)
        do {
            try context.save()
        } catch {
            print("❌ Save failed (delete from swipe):", error)
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
