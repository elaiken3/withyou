//
//  EditInboxItemSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/6/26.
//

import Foundation
import SwiftUI
import SwiftData

struct EditInboxItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startStep: String
    @State private var estimate: Int
    @State private var saveFailed = false

    let item: InboxItem

    init(item: InboxItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _startStep = State(initialValue: item.startStep)
        _estimate = State(initialValue: item.estimateMinutes)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Captured") {
                    TextField("Title", text: $title, axis: .vertical)
                        .listRowBackground(Color.appSurface)
                }

                Section("First step") {
                    TextField("A tiny first step", text: $startStep, axis: .vertical)
                        .listRowBackground(Color.appSurface)
                }

                Section {
                    EstimateMinutesPicker(minutes: $estimate)
                        .listRowBackground(Color.appSurface)
                } header: {
                    Text("Time")
                } footer: {
                    Text("A rough guess is plenty.")
                }

                if saveFailed {
                    Section {
                        Text("That didn’t save. Try again in a moment.")
                            .font(.footnote)
                            .foregroundStyle(.appSecondaryText)
                            .listRowBackground(Color.appSurface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.appBackground)
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(trimmedTitle.isEmpty)
                }
            }
        }
        .tint(.appAccent)
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }

        item.title = trimmedTitle
        item.startStep = startStep.trimmingCharacters(in: .whitespacesAndNewlines)
        item.estimateMinutes = estimate

        do {
            try context.save()
            Haptics.success()
            dismiss()
        } catch {
            Haptics.error()
            print("❌ Save failed (EditInboxItemSheet):", error)
            saveFailed = true
        }
    }
}
