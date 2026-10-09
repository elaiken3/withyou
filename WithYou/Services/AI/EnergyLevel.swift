//
//  EnergyLevel.swift
//  WithYou
//

import Foundation

/// How much energy the person says they have today. Never required; unset reads as "Okay".
///
/// The raw values are also what the cloud AI API expects ("low", "okay", "good").
nonisolated enum EnergyLevel: String, CaseIterable, Identifiable {
    case low, okay, good

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "Low"
        case .okay: return "Okay"
        case .good: return "Good"
        }
    }
}
