//
//  SpeechTranscriber.swift
//  WithYou
//
//  Live speech-to-text for voice capture, on this iPhone whenever the device supports it.
//
//  Threading: the audio tap, the recognition callbacks and the audio-session notifications
//  all arrive on background threads. They are created inside `SpeechPipeline` and
//  `VoicePermissions`, which are `nonisolated`, so they never inherit the app's default
//  main-actor isolation (a main-actor closure called off the main thread traps at runtime).
//  Everything they report hops to the main actor before it touches `SpeechTranscriber`.
//

import Foundation
import AVFoundation
import AVFAudio
import Speech
import Observation

// MARK: - Problems

/// Why listening can't happen right now, in words the person can act on.
nonisolated enum VoiceIssue: Equatable, Sendable {
    case microphoneDenied
    case speechDenied
    case unavailable
    case audioFailed

    var message: String {
        switch self {
        case .microphoneDenied:
            return "WithYou needs the microphone to listen. You can allow it in Settings, or type instead."
        case .speechDenied:
            return "WithYou needs speech recognition to turn your words into text. You can allow it in Settings, or type instead."
        case .unavailable:
            return "Speech recognition isn’t available right now. You can type instead."
        case .audioFailed:
            return "The microphone is busy right now. Try again in a moment, or type instead."
        }
    }

    /// Whether the Settings app can fix it.
    var opensSettings: Bool {
        self == .microphoneDenied || self == .speechDenied
    }
}

// MARK: - Permissions

nonisolated enum VoicePermissions {
    /// Asks for speech recognition and the microphone if they haven't been asked yet.
    /// Returns nil when listening is allowed.
    static func request() async -> VoiceIssue? {
        switch await speechAuthorization() {
        case .authorized:
            break
        case .denied, .restricted, .notDetermined:
            return .speechDenied
        @unknown default:
            return .speechDenied
        }

        let microphoneAllowed = await AVAudioApplication.requestRecordPermission()
        return microphoneAllowed ? nil : .microphoneDenied
    }

    private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            // Called on a background queue.
            SFSpeechRecognizer.requestAuthorization { @Sendable status in
                continuation.resume(returning: status)
            }
        }
    }

    /// The person's own language when it's supported, otherwise US English.
    static func makeRecognizer() -> SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }
}

// MARK: - Audio pipeline (background threads)

nonisolated enum SpeechEvent: Sendable {
    /// The latest words for this round (`nil` when the callback carried none), and whether
    /// recognition has ended. `failed` is true when it ended with an error.
    case recognized(words: String?, isDone: Bool, failed: Bool)
    /// A calm 0…1 microphone level for the on-screen ring.
    case level(Float)
    /// A call, an alarm, or an audio route change took the microphone away.
    case interrupted
}

/// Owns the audio engine, the recognition request and task, and the audio session for
/// one round of listening. Thread-safe: started and stopped from the main actor, fed and
/// finished from audio and recognition threads.
nonisolated final class SpeechPipeline: @unchecked Sendable {

    enum StartError: Error {
        case noMicrophoneInput
    }

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    /// Kept for the whole round; the task doesn't promise to keep it alive.
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var observers: [NSObjectProtocol] = []
    private var tapInstalled = false
    private var audioEnded = false
    private var tornDown = false

    /// Opens the microphone and starts recognising. `onEvent` is called on background threads.
    func start(with recognizer: SFSpeechRecognizer, onEvent: @escaping @Sendable (SpeechEvent) -> Void) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw StartError.noMicrophoneInput
        }

        let throttle = LevelThrottle()
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
            if let level = throttle.level(for: buffer) {
                onEvent(.level(level))
            }
        }

        lock.lock()
        self.recognizer = recognizer
        self.request = request
        tapInstalled = true
        lock.unlock()

        engine.prepare()
        try engine.start()

        let recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let words = result?.bestTranscription.formattedString
            let isDone = error != nil || (result?.isFinal ?? false)
            if isDone {
                self?.tearDown()
            }
            onEvent(.recognized(words: words, isDone: isDone, failed: error != nil))
        }

        lock.lock()
        task = recognitionTask
        lock.unlock()

        observeInterruptions(onEvent: onEvent)
    }

    /// Closes the microphone and lets the recognizer finish the last words.
    func endAudio() {
        lock.lock()
        let alreadyEnded = audioEnded
        audioEnded = true
        let removeTap = tapInstalled
        tapInstalled = false
        let request = self.request
        lock.unlock()
        guard !alreadyEnded else { return }

        if engine.isRunning {
            engine.stop()
        }
        if removeTap {
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
    }

    /// Stops recognising without waiting for the last words.
    func cancel() {
        lock.lock()
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    /// Releases the microphone and the audio session. Safe to call more than once, from any thread.
    func tearDown() {
        endAudio()

        lock.lock()
        let alreadyDown = tornDown
        tornDown = true
        let observers = self.observers
        self.observers = []
        task = nil
        request = nil
        recognizer = nil
        lock.unlock()
        guard !alreadyDown else { return }

        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        // Lets music or a podcast that was ducked come back.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func observeInterruptions(onEvent: @escaping @Sendable (SpeechEvent) -> Void) {
        let center = NotificationCenter.default

        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self?.endAudio()
            onEvent(.interrupted)
        }

        // Headphones plugged in or out: the engine stops itself, so finish gracefully.
        let routeChange = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            self?.endAudio()
            onEvent(.interrupted)
        }

        lock.lock()
        let alreadyDown = tornDown
        if !alreadyDown {
            observers = [interruption, routeChange]
        }
        lock.unlock()

        // Recognition can end (and tear down) before the observers were added.
        if alreadyDown {
            center.removeObserver(interruption)
            center.removeObserver(routeChange)
        }
    }

    /// Root-mean-square amplitude of the first channel.
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sum: Float = 0
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        return (sum / Float(frames)).squareRoot()
    }
}

/// Reports the mic level about ten times a second instead of on every buffer.
/// Only used from the audio tap, which runs on one thread at a time.
nonisolated private final class LevelThrottle: @unchecked Sendable {
    private var lastReport: CFAbsoluteTime = 0

    func level(for buffer: AVAudioPCMBuffer) -> Float? {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastReport >= 0.1 else { return nil }
        lastReport = now
        return VoiceLevel.normalized(rms: SpeechPipeline.rms(of: buffer))
    }
}

// MARK: - Transcriber (main actor)

/// What the voice capture screen observes: the words so far, a calm level, and the state.
@Observable
final class SpeechTranscriber {

    enum State: Equatable {
        case idle
        /// Asking for permission or opening the microphone.
        case preparing
        case listening
        /// The microphone is closed; the last words are still arriving.
        case finishing
    }

    private(set) var state: State = .idle
    /// Everything said (and typed before listening started), joined.
    private(set) var text = ""
    /// 0…1, for the ring around the mic button.
    private(set) var level: Float = 0
    private(set) var issue: VoiceIssue?
    /// Set when listening stopped by itself, for a short hint.
    private(set) var stopReason: VoiceAutoStop.Reason?
    /// True once recognition is known to run on this iPhone.
    private(set) var isOnDevice = false

    var isActive: Bool { state != .idle }

    @ObservationIgnored private var pipeline: SpeechPipeline?
    @ObservationIgnored private var earlierText = ""
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastSpeechAt: Date?
    @ObservationIgnored private var watchdog: Task<Void, Never>?
    /// Bumped whenever a round ends, so late callbacks from it are ignored.
    @ObservationIgnored private var generation = 0

    /// Starts a round of listening. New words are added after `existing`
    /// (what was said or typed before), so tapping the mic again keeps going.
    func start(continuing existing: String) async {
        guard state == .idle else { return }
        issue = nil
        stopReason = nil
        state = .preparing
        generation += 1
        let round = generation

        let problem = await VoicePermissions.request()
        // Closed or stopped while the permission prompt was up.
        guard round == generation, state == .preparing else { return }
        if let problem {
            issue = problem
            state = .idle
            return
        }

        guard let recognizer = VoicePermissions.makeRecognizer(), recognizer.isAvailable else {
            issue = .unavailable
            state = .idle
            return
        }

        earlierText = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        text = earlierText
        isOnDevice = recognizer.supportsOnDeviceRecognition

        let pipeline = SpeechPipeline()
        do {
            try pipeline.start(with: recognizer) { [weak self] event in
                Task { @MainActor in
                    self?.handle(event, round: round)
                }
            }
        } catch {
            pipeline.tearDown()
            issue = .audioFailed
            state = .idle
            return
        }

        self.pipeline = pipeline
        startedAt = Date()
        lastSpeechAt = nil
        state = .listening
        watchForSilence(round: round)
    }

    /// Closes the microphone and keeps the words. The last few may still arrive.
    func stop() {
        switch state {
        case .idle, .finishing:
            return
        case .preparing:
            finish()
        case .listening:
            state = .finishing
            level = 0
            pipeline?.endAudio()

            // If the recognizer never sends its final result, stop waiting after a moment.
            let round = generation
            watchdog?.cancel()
            watchdog = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, self.generation == round, self.state == .finishing else { return }
                self.pipeline?.cancel()
                self.finish()
            }
        }
    }

    /// Stops and waits (briefly) for the last words, so they're included.
    func finishListening() async {
        stop()
        var waited = 0
        while state != .idle, waited < 40 {
            try? await Task.sleep(for: .milliseconds(50))
            waited += 1
        }
        if state != .idle {
            cancel()
        }
    }

    /// Stops right away without waiting for the last words (the screen is closing).
    func cancel() {
        guard state != .idle else { return }
        pipeline?.cancel()
        finish()
    }

    // MARK: - Private

    private func handle(_ event: SpeechEvent, round: Int) {
        guard round == generation else { return }

        switch event {
        case .level(let value):
            guard state == .listening else { return }
            level = value

        case .recognized(let words, let isDone, let failed):
            if let words {
                let joined = VoiceTranscript.joined(earlierText, words)
                if joined != text {
                    text = joined
                    lastSpeechAt = Date()
                }
            }
            guard isDone else { return }
            // Ended by itself right away, with nothing heard: recognition isn't working here
            // (for example, offline without on-device support).
            if failed, state == .listening, lastSpeechAt == nil,
               Date().timeIntervalSince(startedAt) < 2 {
                issue = .unavailable
            }
            finish()

        case .interrupted:
            guard state == .listening else { return }
            stopReason = .interrupted
            stop()
        }
    }

    private func watchForSilence(round: Int) {
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, self.generation == round, self.state == .listening else { return }
                if let reason = VoiceAutoStop.reason(
                    startedAt: self.startedAt,
                    lastSpeechAt: self.lastSpeechAt,
                    now: Date()
                ) {
                    self.stopReason = reason
                    self.stop()
                    return
                }
            }
        }
    }

    private func finish() {
        watchdog?.cancel()
        watchdog = nil
        pipeline?.tearDown()
        pipeline = nil
        generation += 1
        level = 0
        state = .idle
    }
}
