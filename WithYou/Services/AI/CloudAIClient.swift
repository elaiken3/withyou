//
//  CloudAIClient.swift
//  WithYou
//
//  Optional cloud AI: Claude, through WithYou's Supabase function `ai`. Only used after the
//  person turns it on in Settings. Each request carries the text of that one request and an
//  anonymous account token; the server keeps only daily usage counts. Request text is never logged.
//

import Foundation
import OSLog

nonisolated enum CloudAIError: Error, Equatable {
    /// This build has no Supabase project.
    case notConfigured
    /// Skipped for now after the server said it's out of quota or unavailable.
    case paused
    case unauthorized
    case quotaExceeded(retryAfter: TimeInterval?)
    /// 503: the server has no AI key yet, or is starting up.
    case serviceUnavailable
    /// 400 / 413, or a request too large to send.
    case invalidInput
    case server(status: Int)
    case invalidResponse
    case network
}

// MARK: - Wire format (see the API contract)

nonisolated struct CloudAIRequestBody<Input: Encodable>: Encodable {
    let task: String
    let input: Input
}

nonisolated struct CloudAIEnvelope<Payload: Decodable>: Decodable {
    let ok: Bool
    let result: Payload?
}

nonisolated struct CloudCaptureInput: Encodable, Equatable {
    var text: String
    var now: String
    var timezone: String
    var morningHour: Int
    var eveningHour: Int

    enum CodingKeys: String, CodingKey {
        case text, now, timezone
        case morningHour = "morning_hour"
        case eveningHour = "evening_hour"
    }
}

nonisolated struct CloudCaptureResult: Decodable {
    let items: [AICaptureDraft]
}

nonisolated struct CloudBreakDownInput: Encodable, Equatable {
    var title: String
    var currentStep: String

    enum CodingKeys: String, CodingKey {
        case title
        case currentStep = "current_step"
    }
}

nonisolated struct CloudBreakDownResult: Decodable {
    let steps: [String]
}

nonisolated struct CloudStuckInput: Encodable, Equatable {
    var title: String
    var blocker: String
    var energy: String?

    enum CodingKeys: String, CodingKey {
        case title, blocker, energy
    }

    /// Writes `"energy": null` rather than leaving it out.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(blocker, forKey: .blocker)
        try container.encode(energy, forKey: .energy)
    }
}

nonisolated struct CloudStuckResult: Decodable {
    let message: String
    let step: String
    let minutes: Int
}

nonisolated struct CloudNextCandidate: Encodable, Equatable {
    var id: String
    var title: String
    var estimateMinutes: Int?
    var scheduledInMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, title
        case estimateMinutes = "estimate_minutes"
        case scheduledInMinutes = "scheduled_in_minutes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(estimateMinutes, forKey: .estimateMinutes)
        try container.encode(scheduledInMinutes, forKey: .scheduledInMinutes)
    }
}

nonisolated struct CloudNextInput: Encodable, Equatable {
    var energy: String?
    var minutesAvailable: Int?
    var candidates: [CloudNextCandidate]

    enum CodingKeys: String, CodingKey {
        case energy
        case minutesAvailable = "minutes_available"
        case candidates
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(energy, forKey: .energy)
        try container.encode(minutesAvailable, forKey: .minutesAvailable)
        try container.encode(candidates, forKey: .candidates)
    }
}

nonisolated struct CloudNextResult: Decodable {
    let id: String
    let reason: String
    let firstStep: String

    enum CodingKeys: String, CodingKey {
        case id, reason
        case firstStep = "first_step"
    }
}

nonisolated struct CloudTidyInput: Encodable, Equatable {
    var thoughts: [String]
}

nonisolated struct CloudTidyResult: Decodable {
    nonisolated struct Item: Decodable {
        let title: String
        let firstStep: String

        enum CodingKeys: String, CodingKey {
            case title
            case firstStep = "first_step"
        }
    }

    let items: [Item]
}

nonisolated struct CloudEmptyInput: Encodable {}

nonisolated struct CloudDeleteResult: Decodable {
    let deleted: Bool
}

/// Builds each task's `input`, trimmed to the API's limits.
enum CloudAIRequests {
    static func capture(_ text: String, context: CaptureContext) -> CloudCaptureInput {
        CloudCaptureInput(
            text: AIOutput.limitScalars(text.trimmingCharacters(in: .whitespacesAndNewlines), to: AIOutput.maxCaptureTextLength),
            now: isoTimestamp(context.now, timeZone: context.timeZone),
            timezone: context.timeZone.identifier,
            morningHour: AIOutput.clamp(context.morningHour, to: 0...23),
            eveningHour: AIOutput.clamp(context.eveningHour, to: 0...23)
        )
    }

    static func breakDown(title: String, currentStep: String) -> CloudBreakDownInput {
        CloudBreakDownInput(
            title: AIOutput.limitScalars(title.trimmingCharacters(in: .whitespacesAndNewlines), to: 200),
            currentStep: AIOutput.limitScalars(currentStep.trimmingCharacters(in: .whitespacesAndNewlines), to: 200)
        )
    }

    static func stuck(title: String, blocker: StuckBlocker, energy: EnergyLevel?) -> CloudStuckInput {
        CloudStuckInput(
            title: AIOutput.limitScalars(title.trimmingCharacters(in: .whitespacesAndNewlines), to: 200),
            blocker: blocker.rawValue,
            energy: energy?.rawValue
        )
    }

    static func next(
        _ candidates: [NextCandidate],
        energy: EnergyLevel?,
        minutesAvailable: Int?,
        now: Date
    ) -> CloudNextInput {
        CloudNextInput(
            energy: energy?.rawValue,
            minutesAvailable: minutesAvailable.map { AIOutput.clamp($0, to: 5...240) },
            candidates: candidates.map { candidate in
                CloudNextCandidate(
                    id: candidate.id,
                    title: AIOutput.limitScalars(candidate.title, to: 200),
                    estimateMinutes: candidate.estimateMinutes.map { AIOutput.clamp($0, to: AIOutput.estimateRange) },
                    scheduledInMinutes: candidate.scheduledAt.map {
                        AIOutput.clamp(Int(($0.timeIntervalSince(now) / 60).rounded()), to: -1440...10080)
                    }
                )
            }
        )
    }

    static func tidy(_ thoughts: [String]) -> CloudTidyInput {
        CloudTidyInput(thoughts: thoughts.map {
            AIOutput.limitScalars($0.trimmingCharacters(in: .whitespacesAndNewlines), to: 500)
        })
    }

    /// Local time with its offset, e.g. `2026-10-09T14:05:00-04:00`.
    static func isoTimestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Client

final class CloudAIClient {
    static let shared = CloudAIClient(config: CloudAIConfig.fromAppConfig)

    /// The API rejects bodies over 16 KB.
    static let maxBodyBytes = 16 * 1024
    private static let requestTimeout: TimeInterval = 15
    /// How long to skip cloud AI after a 503 (no AI key yet, or the function is starting).
    private static let unavailablePause: TimeInterval = 10 * 60
    private static let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "ai")

    let config: CloudAIConfig?
    let auth: SupabaseAuth?
    private let urlSession: URLSession
    private let now: () -> Date

    /// After "out of requests for today" or "unavailable", cloud AI is skipped until then.
    private(set) var pausedUntil: Date?

    /// Bumped by `deleteCloudData()`. A request that started before a delete never signs in
    /// again afterwards, so no new account appears right after the person deleted theirs.
    private var accountGeneration = 0

    init(
        config: CloudAIConfig?,
        urlSession: URLSession = .shared,
        store: CloudAISessionStore? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.config = config
        self.urlSession = urlSession
        self.now = now
        if let config {
            // A nil store means the Keychain (see SupabaseAuth.init).
            auth = SupabaseAuth(config: config, urlSession: urlSession, store: store, now: now)
        } else {
            auth = nil
        }
    }

    var isConfigured: Bool { config != nil }

    var isPaused: Bool {
        guard let pausedUntil else { return false }
        return pausedUntil > now()
    }

    /// Whether this install has an anonymous account on the server.
    var hasSession: Bool { auth?.session != nil }

    // MARK: - Tasks

    func capture(_ text: String, context: CaptureContext) async throws -> [AICaptureDraft] {
        let input = CloudAIRequests.capture(text, context: context)
        return try await perform(task: "capture", input: input, as: CloudCaptureResult.self).items
    }

    func breakDown(title: String, currentStep: String) async throws -> [String] {
        let input = CloudAIRequests.breakDown(title: title, currentStep: currentStep)
        return try await perform(task: "break_down", input: input, as: CloudBreakDownResult.self).steps
    }

    func stuckHelp(title: String, blocker: StuckBlocker, energy: EnergyLevel?) async throws -> StuckSuggestion {
        let input = CloudAIRequests.stuck(title: title, blocker: blocker, energy: energy)
        let result = try await perform(task: "stuck_help", input: input, as: CloudStuckResult.self)
        return StuckSuggestion(message: result.message, step: result.step, minutes: result.minutes)
    }

    func suggestNext(
        from candidates: [NextCandidate],
        energy: EnergyLevel?,
        minutesAvailable: Int?,
        now: Date
    ) async throws -> NextSuggestion {
        let input = CloudAIRequests.next(candidates, energy: energy, minutesAvailable: minutesAvailable, now: now)
        let result = try await perform(task: "suggest_next", input: input, as: CloudNextResult.self)
        return NextSuggestion(candidateId: result.id, reason: result.reason, firstStep: result.firstStep)
    }

    func tidy(_ thoughts: [String]) async throws -> [TidyItem] {
        let input = CloudAIRequests.tidy(thoughts)
        let result = try await perform(task: "tidy", input: input, as: CloudTidyResult.self)
        return result.items.map { TidyItem(title: $0.title, firstStep: $0.firstStep) }
    }

    /// Deletes everything the server keeps for this install (its usage counts and anonymous
    /// account), then forgets the session here. Returns false when there was nothing to delete.
    @discardableResult
    func deleteCloudData() async throws -> Bool {
        guard let auth else { return false }
        guard auth.session != nil else {
            auth.signOutLocally()
            return false
        }
        do {
            let result = try await perform(
                task: "delete_me",
                input: CloudEmptyInput(),
                as: CloudDeleteResult.self,
                allowNewAccount: false,
                ignorePause: true
            )
            accountGeneration += 1
            auth.signOutLocally()
            return result.deleted
        } catch CloudAIError.unauthorized {
            // The server no longer knows this account, so nothing of it is left there.
            accountGeneration += 1
            auth.signOutLocally()
            return false
        }
    }

    // MARK: - Calls

    /// Sends one task. On a 401 it refreshes the token once, then (when `allowNewAccount`)
    /// signs in again once. Only a rejected refresh token leads to a new sign-in; being offline,
    /// a server error or a rate limit is thrown as is.
    func perform<Input: Encodable, Output: Decodable>(
        task: String,
        input: Input,
        as type: Output.Type,
        allowNewAccount: Bool = true,
        ignorePause: Bool = false
    ) async throws -> Output {
        guard let config, let auth else { throw CloudAIError.notConfigured }
        if !ignorePause && isPaused { throw CloudAIError.paused }

        let body = try Self.encodeBody(task: task, input: input)
        let generation = accountGeneration

        do {
            let token = try await auth.accessToken(signInIfNeeded: allowNewAccount)
            // The person deleted their cloud data while this was waiting: send nothing.
            guard accountGeneration == generation else { throw CloudAIError.unauthorized }
            var reply = try await send(body, token: token, config: config)

            if reply.status == 401 {
                var refreshed: SupabaseSession?
                do {
                    refreshed = try await auth.refresh()
                } catch CloudAIError.unauthorized {
                    // The refresh token was rejected too.
                    refreshed = nil
                }
                if let refreshed {
                    reply = try await send(body, token: refreshed.accessToken, config: config)
                }
            }
            if reply.status == 401, allowNewAccount {
                guard accountGeneration == generation else { throw CloudAIError.unauthorized }
                let session = try await auth.signIn()
                reply = try await send(body, token: session.accessToken, config: config)
            }
            Self.log.info("Cloud AI \(task, privacy: .public): HTTP \(reply.status, privacy: .public)")

            return try Self.decodeResult(status: reply.status, data: reply.data, retryAfter: reply.retryAfter, as: type)
        } catch let error as CloudAIError {
            // With `allowNewAccount`, `.unauthorized` means even a brand-new account was turned
            // away, so trying again on every request would only create more of them.
            notePause(after: error, signInRejected: allowNewAccount && accountGeneration == generation)
            throw error
        }
    }

    private struct Reply {
        let status: Int
        let data: Data
        let retryAfter: TimeInterval?
    }

    private func send(_ body: Data, token: String, config: CloudAIConfig) async throws -> Reply {
        let request = Self.functionRequest(config: config, token: token, body: body)
        let result: (Data, URLResponse)
        do {
            result = try await urlSession.data(for: request)
        } catch {
            throw CloudAIError.network
        }
        guard let http = result.1 as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        return Reply(status: http.statusCode, data: result.0, retryAfter: Self.retryAfter(from: http))
    }

    /// `signInRejected`: an `.unauthorized` came after a new sign-in was tried (or refused).
    /// A plain `.unauthorized` while deleting never pauses.
    private func notePause(after error: CloudAIError, signInRejected: Bool) {
        switch error {
        case .quotaExceeded(let retryAfter):
            let seconds = min(max(retryAfter ?? 3600, 60), 24 * 3600)
            pausedUntil = now().addingTimeInterval(seconds)
        case .serviceUnavailable:
            pausedUntil = now().addingTimeInterval(Self.unavailablePause)
        case .unauthorized where signInRejected:
            pausedUntil = now().addingTimeInterval(Self.unavailablePause)
        default:
            break
        }
    }

    // MARK: - Building and reading (pure)

    static func encodeBody<Input: Encodable>(task: String, input: Input) throws -> Data {
        let body: Data
        do {
            body = try JSONEncoder().encode(CloudAIRequestBody(task: task, input: input))
        } catch {
            throw CloudAIError.invalidInput
        }
        guard body.count <= maxBodyBytes else { throw CloudAIError.invalidInput }
        return body
    }

    static func functionRequest(config: CloudAIConfig, token: String, body: Data) -> URLRequest {
        var request = URLRequest(url: config.functionURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    static func decodeResult<Output: Decodable>(
        status: Int,
        data: Data,
        retryAfter: TimeInterval?,
        as type: Output.Type
    ) throws -> Output {
        guard (200...299).contains(status) else {
            throw error(forStatus: status, retryAfter: retryAfter)
        }
        guard let envelope = try? JSONDecoder().decode(CloudAIEnvelope<Output>.self, from: data),
              envelope.ok,
              let result = envelope.result else {
            throw CloudAIError.invalidResponse
        }
        return result
    }

    static func error(forStatus status: Int, retryAfter: TimeInterval?) -> CloudAIError {
        switch status {
        case 400, 413: return .invalidInput
        case 401: return .unauthorized
        case 429: return .quotaExceeded(retryAfter: retryAfter)
        case 503: return .serviceUnavailable
        default: return .server(status: status)
        }
    }

    /// `Retry-After` in seconds, when the server sent one.
    static func retryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value.trimmingCharacters(in: .whitespaces))
    }
}
