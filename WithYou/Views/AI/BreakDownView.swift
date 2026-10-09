//
//  BreakDownView.swift
//  WithYou
//
//  "Break it down": 2–5 tiny steps for a task. Tapping one makes it the first step.
//  Shown inline (in a card or a Form row) wherever a first step can change. Nothing is
//  saved until the person taps a step, and "Not now" (or leaving) cancels the request.
//

import Foundation
import SwiftUI

/// A new first step and estimate, worked out from the step the person picked.
struct FirstStepChange: Equatable {
    var startStep: String
    var estimateMinutes: Int
}

enum BreakDownChoice {
    /// The first step is meant to take under 2 minutes; later steps around 5.
    static let firstStepMinutes = 2
    static let laterStepMinutes = 5

    /// Picking `step` (at `index` in the list) as the new first step. The estimate only ever
    /// goes down, to fit a step that small, and never below a minute.
    static func change(picking step: String, at index: Int, previousEstimate: Int) -> FirstStepChange {
        let cap = index == 0 ? firstStepMinutes : laterStepMinutes
        let estimate = max(1, min(previousEstimate, cap))
        return FirstStepChange(
            startStep: step.trimmingCharacters(in: .whitespacesAndNewlines),
            estimateMinutes: estimate
        )
    }
}

struct BreakDownView: View {
    let title: String
    let currentStep: String
    /// The step the person tapped and its position (0 is the smallest).
    var onPick: (_ step: String, _ index: Int) -> Void
    var onClose: () -> Void

    @State private var result: AIResult<[String]>?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let result {
                Text("Tap a step to make it your first step.")
                    .font(.footnote)
                    .foregroundStyle(.appSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(result.value.indices, id: \.self) { index in
                    stepButton(result.value[index], index: index)
                }

                AIAttributionLabel(source: result.source)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Breaking it down…")
                        .font(.subheadline)
                        .foregroundStyle(.appSecondaryText)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }

            Button {
                Haptics.tap()
                onClose()
            } label: {
                Text("Not now")
                    .foregroundStyle(.appSecondaryText)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
        .task {
            let steps = await AIService.breakDown(title: title, currentStep: currentStep)
            // Closed while waiting: nothing to show.
            guard !Task.isCancelled else { return }
            result = steps
            let announcement: String = "\(steps.value.count) small steps to choose from."
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    private func stepButton(_ step: String, index: Int) -> some View {
        Button {
            Haptics.tap()
            onPick(step, index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(index + 1).")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.appAccent)

                Text(step)
                    .foregroundStyle(.appPrimaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.appHairline.opacity(0.10), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        // Plain, so each step is its own tap target inside a Form row too.
        .buttonStyle(.plain)
        .accessibilityLabel("Step \(index + 1): \(step)")
        .accessibilityHint("Makes this your first step")
    }
}
