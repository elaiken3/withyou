//
//  CardInputs.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/2/26.
//

import SwiftUI

struct CardTextField: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appSecondaryText)
                    .accessibilityHidden(true)
            }

            // The label lives on the field itself. A label on the container
            // replaced the field for VoiceOver, so it could not be edited.
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .foregroundStyle(.appPrimaryText)
                .tint(.appAccent)
                .accessibilityLabel(placeholder)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFocused ? .appAccent.opacity(0.55) : .appHairline.opacity(0.10),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: .black.opacity(isFocused ? 0.08 : 0.04),
            radius: 12,
            x: 0,
            y: 4
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFocused)
    }
}

struct CardTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var minHeight: CGFloat = 120

    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let icon {
                // Visual caption only; VoiceOver reads the same words from the editor's label.
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.appSecondaryText)
                    Text(placeholder)
                        .font(.footnote)
                        .foregroundStyle(.appSecondaryText)
                }
                .accessibilityHidden(true)
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(icon == nil ? placeholder : "")
                        .foregroundStyle(.appSecondaryText)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                        .accessibilityHidden(true)
                }

                TextEditor(text: $text)
                    .focused($isFocused)
                    .foregroundStyle(.appPrimaryText)
                    .tint(.appAccent)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .accessibilityLabel(placeholder)
            }
            .frame(minHeight: minHeight)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.appSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    isFocused ? .appAccent.opacity(0.55) : .appHairline.opacity(0.10),
                    lineWidth: isFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: .black.opacity(isFocused ? 0.08 : 0.04),
            radius: 10,
            x: 0,
            y: 4
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isFocused)
    }
}

/// A menu of sensible "about how long" values, used instead of a Stepper (GitHub issue #35):
/// one tap to open, one tap to choose, and no long press-and-hold to reach 45 minutes.
struct EstimateMinutesPicker: View {
    var title: String = "About"
    @Binding var minutes: Int

    static let standardValues: [Int] = [1, 2, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120]

    /// The standard values, plus `current` when it is not one of them
    /// (for example a parsed "7 min"), so the picker never shows a blank selection.
    static func values(including current: Int) -> [Int] {
        guard current > 0, !standardValues.contains(current) else { return standardValues }
        return (standardValues + [current]).sorted()
    }

    static func label(for value: Int) -> String {
        value == 1 ? "1 minute" : "\(value) minutes"
    }

    var body: some View {
        Picker(title, selection: $minutes) {
            ForEach(Self.values(including: minutes), id: \.self) { value in
                Text(Self.label(for: value))
                    .tag(value)
            }
        }
        .pickerStyle(.menu)
    }
}
