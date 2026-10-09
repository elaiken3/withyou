//
//  BreathHaptics.swift
//  WithYou
//
//  A soft, continuous vibration that follows the breath: it swells on the inhale,
//  stays almost still on a hold and fades on the exhale.
//

import CoreHaptics
import Foundation

// MARK: - Curve (pure)

/// One point of a haptic intensity curve, in seconds from the start of the curve.
nonisolated struct BreathHapticPoint: Equatable, Sendable {
    let time: TimeInterval
    /// 0…1, scales the vibration's strength.
    let intensity: Double
}

/// The haptic for the rest of the current phase, sampled from the same easing as the orb.
nonisolated struct BreathHapticCurve: Equatable, Sendable {
    /// Core Haptics allows at most 16 control points per curve.
    static let maxPoints = 16

    let kind: BreathPhaseKind
    let duration: TimeInterval
    let points: [BreathHapticPoint]

    /// From where the breath is now to the end of its phase.
    init(state: BreathState, samples: Int = 8) {
        let phase = state.phase
        let start = min(max(state.phaseProgress, 0), 1)
        let duration = max(0, (1 - start) * phase.seconds)
        let count = min(max(samples, 2), Self.maxPoints)

        var points: [BreathHapticPoint] = []
        for sample in 0..<count {
            let fraction = Double(sample) / Double(count - 1)
            let progress = start + (1 - start) * fraction
            let level = BreathEngine.level(from: state.phaseStartLevel, to: phase.endLevel, progress: progress)
            points.append(BreathHapticPoint(time: duration * fraction, intensity: Self.intensity(for: phase.kind, level: level)))
        }

        self.kind = phase.kind
        self.duration = duration
        self.points = points
    }

    /// Follows how full the breath is; a hold is almost still.
    static func intensity(for kind: BreathPhaseKind, level: Double) -> Double {
        let level = min(max(level, 0), 1)
        switch kind {
        case .hold:
            return 0.04 + 0.08 * level
        case .inhale, .topUp, .exhale:
            return 0.05 + 0.95 * level
        }
    }
}

// MARK: - Player

/// Plays `BreathHapticCurve`s with Core Haptics. On hardware without Core Haptics, or if
/// the engine can't start, it falls back to a light tap at each phase change.
final class BreathHaptics {
    private var engine: CHHapticEngine?
    private var player: (any CHHapticPatternPlayer)?
    private var isEngineRunning = false
    /// Set once creating the engine fails, so we stop trying and just tap.
    private var engineUnavailable = false
    private lazy var supportsHaptics: Bool = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    init() {}

    /// Plays the rest of a phase, replacing whatever was playing.
    /// - Parameter tapIfUnavailable: when Core Haptics can't play, tap instead
    ///   (right for a phase change, not for resuming mid-phase).
    func play(_ curve: BreathHapticCurve, tapIfUnavailable: Bool = true) {
        stopPlayer()
        guard let engine = runningEngine() else {
            if tapIfUnavailable { Haptics.tap() }
            return
        }
        guard curve.duration > 0.05, curve.points.count >= 2 else { return }

        do {
            let pattern = try Self.makePattern(for: curve)
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
        } catch {
            // A haptic hiccup is never worth interrupting the breath. Start fresh next phase.
            isEngineRunning = false
        }
    }

    /// Stops any vibration and lets the engine rest (on pause, finish and close).
    func stop() {
        stopPlayer()
        if let engine, isEngineRunning {
            engine.stop(completionHandler: nil)
        }
        isEngineRunning = false
    }

    // MARK: Engine

    private func stopPlayer() {
        if let player {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
        player = nil
    }

    private func runningEngine() -> CHHapticEngine? {
        guard let engine = makeEngineIfNeeded() else { return nil }
        if !isEngineRunning {
            do {
                try engine.start()
                isEngineRunning = true
            } catch {
                return nil
            }
        }
        return engine
    }

    private func makeEngineIfNeeded() -> CHHapticEngine? {
        if let engine { return engine }
        guard supportsHaptics, !engineUnavailable else { return nil }
        do {
            let engine = try CHHapticEngine()
            engine.playsHapticsOnly = true
            // Core Haptics calls these on its own queue. They're built in a nonisolated
            // context and hop to the main actor, so no main-actor code runs off-main.
            engine.resetHandler = Self.makeResetHandler(for: self)
            engine.stoppedHandler = Self.makeStoppedHandler(for: self)
            self.engine = engine
            return engine
        } catch {
            engineUnavailable = true
            return nil
        }
    }

    /// After a reset the engine's players are no longer valid; the next phase starts it again.
    private func engineDidReset() {
        stopPlayer()
        isEngineRunning = false
    }

    /// The system stopped the engine (backgrounding, audio interruption, idle);
    /// the next phase starts it again.
    private func engineDidStop() {
        stopPlayer()
        isEngineRunning = false
    }

    nonisolated private static func makeResetHandler(for owner: BreathHaptics) -> @Sendable () -> Void {
        return { [weak owner] in
            Task { @MainActor in
                owner?.engineDidReset()
            }
        }
    }

    nonisolated private static func makeStoppedHandler(
        for owner: BreathHaptics
    ) -> @Sendable (CHHapticEngine.StoppedReason) -> Void {
        return { [weak owner] _ in
            Task { @MainActor in
                owner?.engineDidStop()
            }
        }
    }

    private static func makePattern(for curve: BreathHapticCurve) throws -> CHHapticPattern {
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.65),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.1)
            ],
            relativeTime: 0,
            duration: curve.duration
        )
        let controlPoints = curve.points.map { point in
            CHHapticParameterCurve.ControlPoint(relativeTime: point.time, value: Float(point.intensity))
        }
        let intensity = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: controlPoints,
            relativeTime: 0
        )
        return try CHHapticPattern(events: [event], parameterCurves: [intensity])
    }
}
