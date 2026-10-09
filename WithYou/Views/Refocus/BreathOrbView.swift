//
//  BreathOrbView.swift
//  WithYou
//
//  The orb and the soft background light in Refocus. Both are drawn from the breath
//  level the Refocus clock provides; neither animates on its own.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

// MARK: - Orb

/// A soft ball of light (a Metal shader) that grows with the breath and slowly changes
/// shape. With Reduce Motion on, a still orb that only brightens and dims.
struct BreathOrbView: View {
    /// How full the breath is, 0…1.
    let level: Double
    /// Seconds of motion so far; drives the slow change of shape.
    let time: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    static let side: CGFloat = 280
    /// The asset catalog's light/dark accent, looked up once.
    private static let dynamicAccent: UIColor = UIColor(named: "AppAccent") ?? UIColor(Color.appAccent)

    var body: some View {
        Group {
            if reduceMotion {
                StillBreathOrb(level: level)
            } else {
                GeometryReader { proxy in
                    Rectangle()
                        .fill(Color.white)
                        .colorEffect(shader(size: proxy.size))
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }

    private func shader(size: CGSize) -> Shader {
        ShaderLibrary.default.breathOrb(
            .float2(Float(size.width), Float(size.height)),
            .float(Float(time)),
            .float(Float(level)),
            .color(accent)
        )
    }

    /// The accent for this light/dark appearance, resolved up front so the shader
    /// always gets the right variant.
    private var accent: Color {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection(userInterfaceStyle: style)
        return Color(uiColor: Self.dynamicAccent.resolvedColor(with: traits))
    }
}

/// Reduce Motion: keeps its size and shape and gently brightens and dims with the breath.
struct StillBreathOrb: View {
    /// How full the breath is, 0…1.
    let level: Double

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.26), Color.appAccent.opacity(0.0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: 140
                    )
                )
                .opacity(0.55 + 0.45 * level)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.appAccent.opacity(0.90), Color.appAccent.opacity(0.22)],
                        center: .topLeading,
                        startRadius: 12,
                        endRadius: 150
                    )
                )
                .frame(width: 190, height: 190)
                .opacity(0.6 + 0.4 * level)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.14 + 0.08 * level), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 110, height: 110)
                .offset(x: -22, y: -30)
                .blendMode(.screen)
        }
    }
}

// MARK: - Ambient Background

/// A wash of accent light behind everything that brightens on the inhale.
/// Only its opacity changes, which stays cheap at full frame rate.
struct AmbientBreathBackground: View {
    /// How full the breath is, 0…1.
    let level: Double

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [Color.appAccent.opacity(0.20), Color.clear],
                center: .center,
                startRadius: 20,
                endRadius: 420
            )
            .opacity(0.5 + 0.5 * level)

            RadialGradient(
                colors: [Color.appAccent.opacity(0.10), Color.clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 380
            )
            .opacity(0.6 + 0.4 * level)
        }
    }
}
