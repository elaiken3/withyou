//
//  AIAttributionLabel.swift
//  WithYou
//
//  A small, quiet note under AI-written text so the person knows where it came from.
//  Nothing is shown for the simple built-in rules.
//

import Foundation
import SwiftUI

enum AIAttribution {
    static func text(for source: AISource) -> String? {
        switch source {
        case .onDevice: return "Suggested on this iPhone"
        case .cloud: return "Suggested by cloud AI"
        case .rules: return nil
        }
    }

    static func systemImage(for source: AISource) -> String {
        source == .cloud ? "cloud" : "iphone"
    }
}

struct AIAttributionLabel: View {
    let source: AISource

    var body: some View {
        if let text = AIAttribution.text(for: source) {
            Label(text, systemImage: AIAttribution.systemImage(for: source))
                .font(.footnote)
                .foregroundStyle(.appSecondaryText)
        }
    }
}
