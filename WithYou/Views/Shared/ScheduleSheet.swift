//
//  ScheduleSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI

struct ScheduleSheet: View {
    let title: String
    let startStep: String
    let estimate: Int
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date = Date()

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).font(.headline)
                Text("Start: \(startStep) (\(estimate) min)")
                    .foregroundStyle(.secondary)

                DatePicker("When", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)

                Button("Schedule") {
                    onPick(date)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .navigationTitle("Schedule")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
