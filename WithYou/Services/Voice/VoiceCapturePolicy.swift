//
//  VoiceCapturePolicy.swift
//  WithYou
//
//  Small, pure rules for voice capture: when listening stops by itself, how a new
//  round of speech joins what was already said, and how loud the mic level looks.
//  `nonisolated` so the audio pipeline and tests can use them from any thread.
//

import Foundation

/// When listening ends on its own. The person can always tap the mic to stop sooner.
nonisolated enum VoiceAutoStop {

    enum Reason: Equatable, Sendable {
        /// A quiet pause after some words.
        case silence
        /// Nothing was heard for a while after the mic opened.
        case nothingHeard
        /// One round of listening is capped so the mic is never left open.
        case timeLimit
        /// A call, an alarm or another app took the microphone.
        case interrupted
    }

    /// Quiet seconds after the last new words.
    static let silenceAfterSpeech: TimeInterval = 2.5
    /// How long to wait for the first words.
    static let waitForFirstWords: TimeInterval = 8
    /// The longest single round of listening.
    static let maximumLength: TimeInterval = 60

    /// Why listening should stop now, or nil to keep going.
    /// `lastSpeechAt` is when the transcript last changed (nil while nothing was heard yet).
    static func reason(startedAt: Date, lastSpeechAt: Date?, now: Date) -> Reason? {
        if now.timeIntervalSince(startedAt) >= maximumLength {
            return .timeLimit
        }
        if let lastSpeechAt {
            return now.timeIntervalSince(lastSpeechAt) >= silenceAfterSpeech ? .silence : nil
        }
        return now.timeIntervalSince(startedAt) >= waitForFirstWords ? .nothingHeard : nil
    }

    /// A short, kind line for the status area after listening stopped by itself.
    static func message(for reason: Reason) -> String {
        switch reason {
        case .silence:
            return "Tap the mic to add more, or Done when you’re ready."
        case .nothingHeard:
            return "I didn’t catch anything. Tap the mic when you’re ready."
        case .timeLimit:
            return "That’s a minute. Tap the mic to keep going."
        case .interrupted:
            return "Paused for a moment. Tap the mic to keep going."
        }
    }
}

nonisolated enum VoiceTranscript {
    /// Joins what was said before (or typed) with a new round of speech.
    static func joined(_ earlier: String, _ latest: String) -> String {
        let first = earlier.trimmingCharacters(in: .whitespacesAndNewlines)
        let second = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        if first.isEmpty { return second }
        if second.isEmpty { return first }
        return first + " " + second
    }
}

nonisolated enum VoiceLevel {
    /// Maps a buffer's RMS amplitude to 0…1 for a calm on-screen level.
    /// About -50 dB (a quiet room) reads as 0 and -10 dB (close, clear speech) as 1.
    static func normalized(rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else { return 0 }
        let decibels = 20 * log10(max(rms, 0.000_01))
        let scaled = (decibels + 50) / 40
        return min(max(scaled, 0), 1)
    }
}
