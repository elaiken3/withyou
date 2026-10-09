//
//  AIService.swift
//  WithYou
//
//  The only entry point features use for AI. Order: Apple's on-device model (when this
//  iPhone has it) → cloud AI (only if the person turned it on) → simple rules. Each attempt
//  has a deadline; anything slow, failing or unusable falls through to the next one, so
//  every call returns something and never throws.
//

import Foundation
import OSLog

/// One provider's try at an answer. `operation` returns nil when the answer wasn't usable.
struct AIAttempt<Value: Sendable> {
    let source: AISource
    let timeout: TimeInterval
    let operation: @Sendable () async throws -> Value?
}

@MainActor
enum AIService {
    static let onDeviceTimeout: TimeInterval = 10
    static let cloudTimeout: TimeInterval = 15

    private static let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "ai")

    /// Apple Intelligence's on-device model is ready (iOS 26+).
    static var isOnDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return OnDeviceAI.isAvailable
        }
        #endif
        return false
    }

    /// The person opted in to cloud AI and this build has a Supabase project.
    static var isCloudEnabled: Bool {
        CloudAISettings.isEnabled && CloudAISettings.isConfigured
    }

    /// "Apple Intelligence" / "Cloud AI" / nil — for small UI attributions like "Suggested on device".
    static var providerName: String? {
        if isOnDeviceAvailable { return "Apple Intelligence" }
        if isCloudEnabled { return "Cloud AI" }
        return nil
    }

    /// Cloud AI, when it's turned on and not paused after a "try later" from the server.
    private static var cloudClient: CloudAIClient? {
        guard isCloudEnabled else { return nil }
        let client = CloudAIClient.shared
        return client.isConfigured && !client.isPaused ? client : nil
    }

    // MARK: - Capture

    /// Turns typed or spoken text into one or more items to review. Empty text gives no items.
    static func capture(_ text: String, context: CaptureContext) async -> AIResult<[CaptureSuggestion]> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return AIResult(value: [], source: .rules) }

        // Lists longer than a model may return, and very long text, stay with the rules
        // so nothing the person said is dropped.
        let lineCount = AIRules.captureLines(trimmed).count
        let tooLong = trimmed.unicodeScalars.count > AIOutput.maxCaptureTextLength
        guard lineCount <= AIOutput.maxCaptureItems, !tooLong else {
            return AIResult(value: AIRules.capture(trimmed, context: context), source: .rules)
        }

        var attempts: [AIAttempt<[CaptureSuggestion]>] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAI.isAvailable {
            attempts.append(AIAttempt(source: .onDevice, timeout: onDeviceTimeout) {
                let drafts = try await OnDeviceAI.capture(trimmed, context: context)
                return await AIOutput.captureSuggestions(from: drafts, text: trimmed, context: context)
            })
        }
        #endif
        if let cloud = cloudClient {
            attempts.append(AIAttempt(source: .cloud, timeout: cloudTimeout) {
                let drafts = try await cloud.capture(trimmed, context: context)
                return await AIOutput.captureSuggestions(from: drafts, text: trimmed, context: context)
            })
        }
        return await firstResult(attempts, task: "capture") {
            AIRules.capture(trimmed, context: context)
        }
    }

    // MARK: - Break down

    /// 2–5 tiny steps for a task, in order.
    static func breakDown(title: String, currentStep: String = "") async -> AIResult<[String]> {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return AIResult(value: AIRules.breakDown(title: title, currentStep: currentStep), source: .rules)
        }

        var attempts: [AIAttempt<[String]>] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAI.isAvailable {
            attempts.append(AIAttempt(source: .onDevice, timeout: onDeviceTimeout) {
                let steps = try await OnDeviceAI.breakDown(title: cleanTitle, currentStep: currentStep)
                return await AIOutput.breakDownSteps(from: steps, currentStep: currentStep)
            })
        }
        #endif
        if let cloud = cloudClient {
            attempts.append(AIAttempt(source: .cloud, timeout: cloudTimeout) {
                let steps = try await cloud.breakDown(title: cleanTitle, currentStep: currentStep)
                return await AIOutput.breakDownSteps(from: steps, currentStep: currentStep)
            })
        }
        return await firstResult(attempts, task: "break_down") {
            AIRules.breakDown(title: cleanTitle, currentStep: currentStep)
        }
    }

    // MARK: - Stuck

    /// One kind sentence, one tiny step, and how long to try it.
    static func stuckHelp(title: String, blocker: StuckBlocker, energy: EnergyLevel?) async -> AIResult<StuckSuggestion> {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else {
            return AIResult(value: AIRules.stuckHelp(title: title, blocker: blocker, energy: energy), source: .rules)
        }

        var attempts: [AIAttempt<StuckSuggestion>] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAI.isAvailable {
            attempts.append(AIAttempt(source: .onDevice, timeout: onDeviceTimeout) {
                let raw = try await OnDeviceAI.stuckHelp(title: cleanTitle, blocker: blocker, energy: energy)
                return await AIOutput.stuckSuggestion(raw)
            })
        }
        #endif
        if let cloud = cloudClient {
            attempts.append(AIAttempt(source: .cloud, timeout: cloudTimeout) {
                let raw = try await cloud.stuckHelp(title: cleanTitle, blocker: blocker, energy: energy)
                return await AIOutput.stuckSuggestion(raw)
            })
        }
        return await firstResult(attempts, task: "stuck_help") {
            AIRules.stuckHelp(title: cleanTitle, blocker: blocker, energy: energy)
        }
    }

    // MARK: - Next

    /// One thing to do now, with a gentle reason and a first step. Nil when there are no candidates.
    static func suggestNext(
        from candidates: [NextCandidate],
        energy: EnergyLevel?,
        minutesAvailable: Int?
    ) async -> AIResult<NextSuggestion>? {
        let usable = AIOutput.usableCandidates(candidates)
        guard let fallback = AIRules.suggestNext(from: usable, energy: energy, minutesAvailable: minutesAvailable) else {
            return nil
        }
        let now = Date()

        var attempts: [AIAttempt<NextSuggestion>] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAI.isAvailable {
            attempts.append(AIAttempt(source: .onDevice, timeout: onDeviceTimeout) {
                let raw = try await OnDeviceAI.suggestNext(
                    from: usable, energy: energy, minutesAvailable: minutesAvailable, now: now
                )
                return await AIOutput.nextSuggestion(raw, candidates: usable)
            })
        }
        #endif
        if let cloud = cloudClient {
            attempts.append(AIAttempt(source: .cloud, timeout: cloudTimeout) {
                let raw = try await cloud.suggestNext(
                    from: usable, energy: energy, minutesAvailable: minutesAvailable, now: now
                )
                return await AIOutput.nextSuggestion(raw, candidates: usable)
            })
        }
        return await firstResult(attempts, task: "suggest_next") { fallback }
    }

    // MARK: - Tidy

    /// A title and first step for each brain-dump thought, in the same order and count.
    static func tidy(_ thoughts: [String]) async -> AIResult<[TidyItem]> {
        let fallback = AIRules.tidy(thoughts)

        // Blank thoughts keep their rules-based item; the rest go to the model together.
        let indices = thoughts.indices.filter {
            !thoughts[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let sendable = indices.map { thoughts[$0] }
        guard !sendable.isEmpty, sendable.count <= AIOutput.maxThoughts else {
            return AIResult(value: fallback, source: .rules)
        }
        let subsetFallback = indices.map { fallback[$0] }

        var attempts: [AIAttempt<[TidyItem]>] = []
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), OnDeviceAI.isAvailable, sendable.count <= OnDeviceAI.maxTidyThoughts {
            attempts.append(AIAttempt(source: .onDevice, timeout: onDeviceTimeout) {
                let raw = try await OnDeviceAI.tidy(sendable)
                return await merged(raw, into: fallback, at: indices, subsetFallback: subsetFallback)
            })
        }
        #endif
        if let cloud = cloudClient {
            attempts.append(AIAttempt(source: .cloud, timeout: cloudTimeout) {
                let raw = try await cloud.tidy(sendable)
                return await merged(raw, into: fallback, at: indices, subsetFallback: subsetFallback)
            })
        }
        return await firstResult(attempts, task: "tidy") { fallback }
    }

    /// Puts the model's items back at their thoughts' positions. Nil if they don't line up.
    static func merged(
        _ raw: [TidyItem],
        into fallback: [TidyItem],
        at indices: [Int],
        subsetFallback: [TidyItem]
    ) -> [TidyItem]? {
        guard let items = AIOutput.tidyItems(raw, fallback: subsetFallback), items.count == indices.count else {
            return nil
        }
        var result = fallback
        for (position, index) in indices.enumerated() where result.indices.contains(index) {
            result[index] = items[position]
        }
        return result
    }

    // MARK: - Provider chain

    /// The first attempt that answers in time with something usable, or the rules.
    static func firstResult<Value: Sendable>(
        _ attempts: [AIAttempt<Value>],
        task: String,
        fallback: () -> Value
    ) async -> AIResult<Value> {
        for attempt in attempts {
            if Task.isCancelled { break }
            do {
                let value = try await AITimeout.run(seconds: attempt.timeout, operation: attempt.operation)
                if let value {
                    return AIResult(value: value, source: attempt.source)
                }
                log.info("AI \(task, privacy: .public) via \(attempt.source.rawValue, privacy: .public): unusable answer")
            } catch {
                // Only the kind of error, never the person's words.
                let kind = String(describing: type(of: error))
                log.info("AI \(task, privacy: .public) via \(attempt.source.rawValue, privacy: .public) failed: \(kind, privacy: .public)")
            }
        }
        return AIResult(value: fallback(), source: .rules)
    }
}
