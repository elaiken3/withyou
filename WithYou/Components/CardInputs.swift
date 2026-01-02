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

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.appSecondaryText)
            }

            TextField(placeholder, text: $text)
                .focused($isFocused)
                .foregroundStyle(.appPrimaryText)
                .tint(.appAccent)
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
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .accessibilityLabel(placeholder)
    }
}

struct CardTextEditor: View {
    let placeholder: String
    @Binding var text: String
    var icon: String? = nil
    var minHeight: CGFloat = 120

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let icon {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.appSecondaryText)
                    Text(placeholder)
                        .font(.footnote)
                        .foregroundStyle(.appSecondaryText)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(icon == nil ? placeholder : "")
                        .foregroundStyle(.appSecondaryText)
                        .padding(.top, 10)
                        .padding(.leading, 6)
                }

                TextEditor(text: $text)
                    .focused($isFocused)
                    .foregroundStyle(.appPrimaryText)
                    .tint(.appAccent)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
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
        .animation(.easeOut(duration: 0.18), value: isFocused)
        .accessibilityLabel(placeholder)
    }
}
