//
//  EditInboxItemSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/6/26.
//

import SwiftUI
import SwiftData

struct EditInboxItemSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var startStep: String
    @State private var estimate: Int

    let item: InboxItem

    init(item: InboxItem) {
        self.item = item
        _title = State(initialValue: item.title)
        _startStep = State(initialValue: item.startStep)
        _estimate = State(initialValue: item.estimateMinutes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("What is this?") {
                    TextField("Title", text: $title)
                }

                Section("First step") {
                    TextField("Start step", text: $startStep)
                }

                Section("Time") {
                    Stepper("\(estimate) minutes", value: $estimate, in: 1...60)
                }
            }
            .navigationTitle("Edit")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                title = item.title
                startStep = item.startStep
                estimate = item.estimateMinutes
            }
        }
    }

    private func save() {
        item.title = title
        item.startStep = startStep
        item.estimateMinutes = estimate

        try? context.save()
        dismiss()
    }
}
