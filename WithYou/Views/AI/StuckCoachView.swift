//
//  StuckCoachView.swift
//  WithYou
//
//  The "I’m stuck" coach: the person names what’s in the way, and gets one kind sentence
//  and one tiny step to try for a few minutes. Optional, and easy to leave.
//

import Foundation
import SwiftUI

enum StuckCoachText {
    static let question = "What’s in the way?"

    static func tryTitle(minutes: Int) -> String {
        minutes == 1 ? "Try it for 1 minute" : "Try it for \(minutes) minutes"
    }
}

/// One chip per blocker. Tapping one asks for a suggestion.
struct StuckBlockerChips: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var onSelect: (StuckBlocker) -> Void

    /// As many chips per row as fit; one per row at accessibility text sizes, so labels
    /// never break mid-word.
    private var columns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible(), spacing: 8, alignment: .leading)]
        }
        return [GridItem(.adaptive(minimum: 150), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(StuckBlocker.allCases) { blocker in
                Button {
                    Haptics.tap()
                    onSelect(blocker)
                } label: {
                    Text(blocker.label)
                        .font(.subheadline)
                        .foregroundStyle(.appPrimaryText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.appSurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.appHairline.opacity(0.10), lineWidth: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Suggests one small way through")
            }
        }
    }
}

/// The coach's answer for one blocker: a kind sentence, a tiny step, and how long to try it.
/// Asks when it appears; removing it (Something else, Not now, closing) cancels the request.
struct StuckCoachSection: View {
    let title: String
    let blocker: StuckBlocker
    let energy: EnergyLevel?
    var onTry: (StuckSuggestion) -> Void
    var onSomethingElse: () -> Void
    var onNotNow: () -> Void

    @State private var result: AIResult<StuckSuggestion>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(blocker.label)
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)

            if let result {
                suggestion(result)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding one small step…")
                        .foregroundStyle(.appSecondaryText)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }

            buttons
        }
        .task {
            let help = await AIService.stuckHelp(title: title, blocker: blocker, energy: energy)
            guard !Task.isCancelled else { return }
            result = help
            let announcement: String = "\(help.value.message) Try: \(help.value.step)"
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    @ViewBuilder
    private func suggestion(_ result: AIResult<StuckSuggestion>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.value.message)
                .foregroundStyle(.appPrimaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text("Try: \(result.value.step)")
                .foregroundStyle(.appSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)

        AIAttributionLabel(source: result.source)
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            if let result {
                Button {
                    Haptics.tap()
                    onTry(result.value)
                } label: {
                    Text(StuckCoachText.tryTitle(minutes: result.value.minutes))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                Haptics.tap()
                onSomethingElse()
            } label: {
                Text("Something else")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Pick a different reason")

            Button {
                Haptics.tap()
                onNotNow()
            } label: {
                Text("Not now")
                    .foregroundStyle(.appSecondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderless)
            .controlSize(.large)
        }
        .padding(.top, 2)
    }
}
