//
//  ScheduleSheet.swift
//  WithYou
//
//  Created by Eugene Aiken on 12/24/25.
//

import SwiftUI

import SwiftUI

struct ScheduleSheetV2: View {
    let title: String
    let startStep: String
    let estimate: Int
    var onPick: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var date: Date = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {

                        // Summary card
                        VStack(alignment: .leading, spacing: 8) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.appPrimaryText)

                            Text("Start: \(startStep) (\(estimate) min)")
                                .font(.subheadline)
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

                        // Date picker card
                        VStack(alignment: .leading, spacing: 10) {
                            Text("When")
                                .font(.headline)
                                .foregroundStyle(.appPrimaryText)

                            DatePicker(
                                "",
                                selection: $date,
                                displayedComponents: [.date, .hourAndMinute]
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .tint(.appAccent)
                            // Force the picker to respect your environment
                            .colorScheme(scheme)
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

                        // Action
                        Button {
                            Haptics.tap()
                            onPick(date)
                            Haptics.success()
                            dismiss()
                        } label: {
                            Text("Schedule")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.appAccent)

                        Spacer(minLength: 20)
                    }
                    .padding()
                }
            }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .tint(.appAccent)
        }
        .presentationBackground(Color.appBackground)
    }
}
