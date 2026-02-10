//
//  InboxDetailView.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/25/25.
//

import SwiftUI
import SwiftData

struct InboxDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: InboxItem

    @State private var showSchedule = false
    @State private var isDeleting = false
    @State private var confirmNotNeeded = false
    @State private var showEdit = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            List {
                Section("Captured") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(item.title)
                            .font(.headline)
                            .foregroundStyle(.appPrimaryText)

                        Text("Start: \(item.startStep) (\(item.estimateMinutes) min)")
                            .foregroundStyle(.appSecondaryText)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.appSurface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.appHairline.opacity(0.10), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.03), radius: 8, x: 0, y: 4)
                    .padding(.vertical, 6)
                    .listRowBackground(Color.appBackground)
                    .listRowSeparator(.hidden)
                }

                Section("Actions") {
                    Button {
                        Haptics.tap()
                        showSchedule = true
                    } label: {
                        Label("Schedule", systemImage: "calendar.badge.plus")
                    }
                    .listRowBackground(Color.appBackground)

                    Button {
                        Haptics.tap()
                        makeSmaller()
                    } label: {
                        Label("Make smaller (2 min)", systemImage: "scissors")
                    }
                    .listRowBackground(Color.appBackground)

                    Button(role: .destructive) {
                        Haptics.tap()
                        confirmNotNeeded = true
                    } label: {
                        Label("Not needed", systemImage: "trash")
                    }
                    .disabled(isDeleting)
                    .listRowBackground(Color.appBackground)
                    
                    Button {
                        Haptics.tap()
                        CompletionStore.completeInboxItem(item, in: context)
                        Haptics.success()
                        dismiss()
                    } label: {
                        Label("Mark completed", systemImage: "checkmark.circle")
                    }
                    .listRowBackground(Color.appBackground)

                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
        }
        .navigationTitle("Inbox Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showEdit = true
                }
            }
        }
        .tint(.appAccent)
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
            isPresented: $confirmNotNeeded
        ) {
            Button("Let go", role: .destructive) {
                deleteItem()
            }
            Button("Keep", role: .cancel) { }
        } message: {
            Text("You don’t have to do everything.")
        }
    }

    private func makeSmaller() {
        item.startStep = makeSmallerStep(for: item.title)
        item.estimateMinutes = 2

        do {
            try context.save()
            Haptics.success()
        } catch {
            Haptics.error()
            print("❌ Save failed (makeSmaller):", error)
        }
    }

    private func makeSmallerStep(for title: String) -> String {
        "Open what you need and do the smallest possible step for 2 minutes."
    }

    private func deleteItem() {
        guard !isDeleting else { return }
        isDeleting = true

        context.delete(item)

        do {
            try context.save()
            Haptics.success()
            dismiss() // pop back immediately so it “disappears”
        } catch {
            Haptics.error()
            print("❌ Save failed (delete):", error)
            isDeleting = false
        }
    }

    private func schedule(date: Date) {
        Haptics.tap()
        Task {
            do {
                _ = try await ReminderStore.createAndSchedule(
                    title: item.title,
                    startStep: item.startStep,
                    estimateMinutes: item.estimateMinutes,
                    scheduledAt: date,
                    in: context
                )
                context.delete(item)
                try context.save()
                Haptics.success()
                dismiss() // scheduled items leave Inbox
            } catch {
                Haptics.error()
                print("❌ Save failed (schedule):", error)
            }
        }
    }
}
