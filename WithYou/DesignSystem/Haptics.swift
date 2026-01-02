//
//  Haptics.swift
//  WithYou
//
//  Created by Eugene Aiken on 1/2/26.
//

import UIKit

enum Haptics {
    // Good for taps like Save/Schedule/Start
    static func tap() {
        let gen = UIImpactFeedbackGenerator(style: .soft)
        gen.prepare()
        gen.impactOccurred()
    }

    // Good for success states (saved, scheduled, started)
    static func success() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.success)
    }

    // Gentle warning (try again)
    static func warning() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.warning)
    }

    // Error (couldn’t save)
    static func error() {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(.error)
    }
}
