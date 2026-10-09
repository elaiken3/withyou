//
//  AICloudClientTests.swift
//  WithYouTests
//
//  The cloud AI client against a stubbed network: request shape and headers, the API
//  contract's sample responses, error mapping, and the anonymous sign-in / refresh flow.
//

import Foundation
import XCTest
@testable import WithYou

/// Answers every request from `handler` and remembers what was sent.
final class AIStubURLProtocol: URLProtocol {
    struct Sent {
        let request: URLRequest
        let body: Data
    }

    typealias Handler = @Sendable (URLRequest, Data) throws -> (status: Int, headers: [String: String], body: Data)

    /// Shared with the loading threads URLSession uses, so every access takes the lock.
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var handler: Handler?
        private var sent: [Sent] = []

        func withLock<T>(_ body: (inout Handler?, inout [Sent]) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&handler, &sent)
        }
    }

    private static let state = State()

    static var handler: Handler? {
        get { state.withLock { handler, _ in handler } }
        set { state.withLock { handler, _ in handler = newValue } }
    }

    static var sent: [Sent] {
        state.withLock { _, sent in sent }
    }

    static func reset() {
        state.withLock { handler, sent in
            handler = nil
            sent = []
        }
    }

    static func count(path: String) -> Int {
        sent.filter { $0.request.url?.path == path }.count
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.bodyData(of: request)
        let sentRequest = Sent(request: request, body: body)
        let handler = Self.state.withLock { (handler, sent) -> Handler? in
            sent.append(sentRequest)
            return handler
        }

        guard let handler, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        do {
            let reply = try handler(request, body)
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: reply.body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    /// URLSession moves the body into a stream before it reaches a URLProtocol.
    private static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

@MainActor
final class AIMemorySessionStore: CloudAISessionStore {
    var stored: SupabaseSession?

    init(_ session: SupabaseSession? = nil) {
        stored = session
    }

    func load() -> SupabaseSession? { stored }
    func save(_ session: SupabaseSession) { stored = session }
    func clear() { stored = nil }
}

/// Sample replies from the API contract. Not actor-isolated, so stub handlers can use them.
enum AICloudFixtures {
    static let functionPath = "/functions/v1/ai"
    static let signUpPath = "/auth/v1/signup"
    static let tokenPath = "/auth/v1/token"

    static func json(_ text: String) -> Data { Data(text.utf8) }

    static func authReply(token: String, refresh: String, expiresAt: Date) -> Data {
        json("""
        {"access_token": "\(token)", "token_type": "bearer", "expires_in": 3600,
         "expires_at": \(Int(expiresAt.timeIntervalSince1970)), "refresh_token": "\(refresh)",
         "user": {"id": "user-1", "is_anonymous": true}}
        """)
    }

    static var stepsReply: Data {
        json(#"{"ok": true, "task": "break_down", "result": {"steps": ["Open Mail.", "Write one line."]}}"#)
    }

    static var unauthorizedReply: Data {
        json(#"{"ok": false, "error": "unauthorized", "message": "Please sign in again."}"#)
    }

    static func object(_ data: Data) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}

@MainActor
final class AICloudClientTests: XCTestCase {
    private typealias F = AICloudFixtures

    private let config = CloudAIConfig(baseURL: URL(string: "https://example.supabase.co")!, anonKey: "anon-key")
    private let now = Date(timeIntervalSince1970: 1_791_000_000)

    /// A client whose requests go to `AIStubURLProtocol` (cleared here for each test).
    private func makeClient(store: AIMemorySessionStore) -> CloudAIClient {
        AIStubURLProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStubURLProtocol.self]
        let fixedNow = now
        return CloudAIClient(
            config: config,
            urlSession: URLSession(configuration: configuration),
            store: store,
            now: { fixedNow }
        )
    }

    private func validSession(token: String = "token-0") -> SupabaseSession {
        SupabaseSession(accessToken: token, refreshToken: "refresh-0", expiresAt: now.addingTimeInterval(3600), userId: "user-0")
    }

    private func expectError(_ expected: CloudAIError, _ work: () async throws -> Void) async {
        do {
            try await work()
            XCTFail("Expected \(expected)")
        } catch let error as CloudAIError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Configuration

    func testConfigURLs() {
        XCTAssertEqual(config.functionURL.absoluteString, "https://example.supabase.co/functions/v1/ai")
        XCTAssertEqual(config.signUpURL.absoluteString, "https://example.supabase.co/auth/v1/signup")
        XCTAssertEqual(config.refreshURL.absoluteString, "https://example.supabase.co/auth/v1/token?grant_type=refresh_token")
    }

    func testSupabaseHostFromBuildSettings() {
        XCTAssertEqual(AppConfig.supabaseURL(fromHost: "abcd.supabase.co")?.absoluteString, "https://abcd.supabase.co")
        XCTAssertEqual(AppConfig.supabaseURL(fromHost: " \"abcd.supabase.co\" ")?.absoluteString, "https://abcd.supabase.co")
        XCTAssertEqual(AppConfig.supabaseURL(fromHost: "https://abcd.supabase.co")?.absoluteString, "https://abcd.supabase.co")
        XCTAssertNil(AppConfig.supabaseURL(fromHost: "$(WITHYOU_SUPABASE_HOST)"))
        XCTAssertNil(AppConfig.supabaseURL(fromHost: ""))
        XCTAssertNil(AppConfig.supabaseURL(fromHost: "https:"))
        XCTAssertNil(AppConfig.supabaseURL(fromHost: nil))
        XCTAssertNil(AppConfig.cleanedValue("  "))
        XCTAssertEqual(AppConfig.cleanedValue(" sb_publishable_123 "), "sb_publishable_123")
    }

    // MARK: - Requests

    func testFunctionRequestHeaders() {
        let request = CloudAIClient.functionRequest(config: config, token: "abc", body: Data("{}".utf8))
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://example.supabase.co/functions/v1/ai")
        XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
    }

    func testCaptureBodyMatchesTheContract() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T18:05:00Z"))
        let context = CaptureContext(now: date, timeZone: zone, morningHour: 8, eveningHour: 20)

        let body = try CloudAIClient.encodeBody(task: "capture", input: CloudAIRequests.capture("  Email landlord  ", context: context))
        let object = F.object(body)
        let input = try XCTUnwrap(object["input"] as? [String: Any])

        XCTAssertEqual(object["task"] as? String, "capture")
        XCTAssertEqual(input["text"] as? String, "Email landlord")
        XCTAssertEqual(input["now"] as? String, "2026-10-09T14:05:00-04:00")
        XCTAssertEqual(input["timezone"] as? String, "America/New_York")
        XCTAssertEqual(input["morning_hour"] as? Int, 8)
        XCTAssertEqual(input["evening_hour"] as? Int, 20)
    }

    func testTimestampInUTCUsesZ() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-09T18:05:00Z"))
        XCTAssertEqual(CloudAIRequests.isoTimestamp(date, timeZone: zone), "2026-10-09T18:05:00Z")
    }

    func testStuckBodySendsNullEnergy() throws {
        let body = try CloudAIClient.encodeBody(
            task: "stuck_help",
            input: CloudAIRequests.stuck(title: "Email landlord", blocker: .tooBig, energy: nil)
        )
        let input = try XCTUnwrap(F.object(body)["input"] as? [String: Any])
        XCTAssertEqual(input["blocker"] as? String, "too_big")
        XCTAssertTrue(input["energy"] is NSNull, "energy is sent as null")

        let withEnergy = try CloudAIClient.encodeBody(
            task: "stuck_help",
            input: CloudAIRequests.stuck(title: "Email landlord", blocker: .boring, energy: .low)
        )
        XCTAssertEqual((F.object(withEnergy)["input"] as? [String: Any])?["energy"] as? String, "low")
    }

    func testSuggestNextBodyClampsNumbers() throws {
        let candidates = [
            NextCandidate(id: "a", title: "Email landlord", estimateMinutes: 500, scheduledAt: now.addingTimeInterval(90 * 60)),
            NextCandidate(id: "b", title: "Call mom", estimateMinutes: nil, scheduledAt: now.addingTimeInterval(-3 * 86_400)),
            NextCandidate(id: "c", title: "Plan trip", estimateMinutes: 0, scheduledAt: now.addingTimeInterval(30 * 86_400))
        ]
        let input = CloudAIRequests.next(candidates, energy: .good, minutesAvailable: 2, now: now)
        XCTAssertEqual(input.minutesAvailable, 5)
        XCTAssertEqual(input.candidates.map(\.estimateMinutes), [240, nil, 1])
        XCTAssertEqual(input.candidates.map(\.scheduledInMinutes), [90, -1440, 10080])

        let body = try CloudAIClient.encodeBody(task: "suggest_next", input: input)
        let sent = try XCTUnwrap(F.object(body)["input"] as? [String: Any])
        let list = try XCTUnwrap(sent["candidates"] as? [[String: Any]])
        XCTAssertEqual(sent["energy"] as? String, "good")
        XCTAssertTrue(list[1]["estimate_minutes"] is NSNull)
        XCTAssertEqual(list[0]["scheduled_in_minutes"] as? Int, 90)

        let noEnergy = try CloudAIClient.encodeBody(
            task: "suggest_next",
            input: CloudAIRequests.next(candidates, energy: nil, minutesAvailable: nil, now: now)
        )
        let noEnergyInput = try XCTUnwrap(F.object(noEnergy)["input"] as? [String: Any])
        XCTAssertTrue(noEnergyInput["energy"] is NSNull)
        XCTAssertTrue(noEnergyInput["minutes_available"] is NSNull)
    }

    func testBreakDownAndTidyBodies() throws {
        let body = try CloudAIClient.encodeBody(
            task: "break_down",
            input: CloudAIRequests.breakDown(title: " Email landlord ", currentStep: "")
        )
        let breakDown = try XCTUnwrap(F.object(body)["input"] as? [String: Any])
        XCTAssertEqual(breakDown["title"] as? String, "Email landlord")
        XCTAssertEqual(breakDown["current_step"] as? String, "")

        let longThought = String(repeating: "a", count: 900)
        let tidy = CloudAIRequests.tidy([" call mom ", longThought])
        XCTAssertEqual(tidy.thoughts.first, "call mom")
        XCTAssertEqual(tidy.thoughts.last?.count, 500)
    }

    func testOversizedBodiesAreNotSent() {
        let huge = CloudTidyInput(thoughts: Array(repeating: String(repeating: "é", count: 500), count: 30))
        XCTAssertThrowsError(try CloudAIClient.encodeBody(task: "tidy", input: huge)) { error in
            XCTAssertEqual(error as? CloudAIError, .invalidInput)
        }
    }

    // MARK: - Contract samples

    func testDecodesEveryTaskResult() throws {
        let capture = try CloudAIClient.decodeResult(status: 200, data: F.json("""
        {"ok": true, "task": "capture", "result": {"items": [
          {"title": "Email landlord", "first_step": "Open Mail.", "estimate_minutes": 4,
           "when": {"day_offset": 1, "hour": 9, "minute": 0}},
          {"title": "Buy milk", "first_step": "Add it to the list.", "estimate_minutes": 3, "when": null}
        ]}}
        """), retryAfter: nil, as: CloudCaptureResult.self)
        XCTAssertEqual(capture.items.count, 2)
        XCTAssertEqual(capture.items[0].when, CaptureWhen(dayOffset: 1, hour: 9, minute: 0))
        XCTAssertNil(capture.items[1].when)

        let steps = try CloudAIClient.decodeResult(status: 200, data: F.stepsReply, retryAfter: nil, as: CloudBreakDownResult.self)
        XCTAssertEqual(steps.steps, ["Open Mail.", "Write one line."])

        let stuck = try CloudAIClient.decodeResult(status: 200, data: F.json("""
        {"ok": true, "task": "stuck_help", "result": {"message": "Big things feel heavy.", "step": "Open the file.", "minutes": 3}}
        """), retryAfter: nil, as: CloudStuckResult.self)
        XCTAssertEqual(stuck.minutes, 3)

        let next = try CloudAIClient.decodeResult(status: 200, data: F.json("""
        {"ok": true, "task": "suggest_next", "result": {"id": "b", "reason": "It’s quick.", "first_step": "Find the number."}}
        """), retryAfter: nil, as: CloudNextResult.self)
        XCTAssertEqual(next.id, "b")
        XCTAssertEqual(next.firstStep, "Find the number.")

        let tidy = try CloudAIClient.decodeResult(status: 200, data: F.json("""
        {"ok": true, "task": "tidy", "result": {"items": [{"title": "Call mom", "first_step": "Find her number."}]}}
        """), retryAfter: nil, as: CloudTidyResult.self)
        XCTAssertEqual(tidy.items.first?.firstStep, "Find her number.")

        let deleted = try CloudAIClient.decodeResult(status: 200, data: F.json("""
        {"ok": true, "task": "delete_me", "result": {"deleted": true}}
        """), retryAfter: nil, as: CloudDeleteResult.self)
        XCTAssertTrue(deleted.deleted)
    }

    func testErrorStatusesMapToErrors() {
        XCTAssertEqual(CloudAIClient.error(forStatus: 400, retryAfter: nil), .invalidInput)
        XCTAssertEqual(CloudAIClient.error(forStatus: 413, retryAfter: nil), .invalidInput)
        XCTAssertEqual(CloudAIClient.error(forStatus: 401, retryAfter: nil), .unauthorized)
        XCTAssertEqual(CloudAIClient.error(forStatus: 429, retryAfter: 120), .quotaExceeded(retryAfter: 120))
        XCTAssertEqual(CloudAIClient.error(forStatus: 503, retryAfter: nil), .serviceUnavailable)
        XCTAssertEqual(CloudAIClient.error(forStatus: 502, retryAfter: nil), .server(status: 502))
        XCTAssertEqual(CloudAIClient.error(forStatus: 500, retryAfter: nil), .server(status: 500))
    }

    func testNotOkBodiesAreRejected() {
        let notOk = F.json(#"{"ok": false, "error": "internal", "message": "Something went wrong."}"#)
        XCTAssertThrowsError(try CloudAIClient.decodeResult(status: 200, data: notOk, retryAfter: nil, as: CloudBreakDownResult.self)) { error in
            XCTAssertEqual(error as? CloudAIError, .invalidResponse)
        }
        XCTAssertThrowsError(try CloudAIClient.decodeResult(status: 200, data: F.json("not json"), retryAfter: nil, as: CloudBreakDownResult.self))
    }

    func testAuthResponseExpiry() throws {
        let withExpiresAt = try JSONDecoder().decode(SupabaseAuthResponse.self, from: F.authReply(
            token: "t", refresh: "r", expiresAt: now.addingTimeInterval(1800)
        ))
        let session = withExpiresAt.session(now: now)
        XCTAssertEqual(session.expiresAt.timeIntervalSince1970, now.addingTimeInterval(1800).timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(session.userId, "user-1")

        let withoutExpiresAt = try JSONDecoder().decode(SupabaseAuthResponse.self, from: F.json("""
        {"access_token": "t", "refresh_token": "r", "expires_in": 600}
        """))
        let fallback = withoutExpiresAt.session(now: now, previousUserId: "user-0")
        XCTAssertEqual(fallback.expiresAt, now.addingTimeInterval(600))
        XCTAssertEqual(fallback.userId, "user-0")
    }

    // MARK: - Network flow

    func testFirstCallSignsInAnonymously() async throws {
        let store = AIMemorySessionStore()
        let client = makeClient(store: store)
        let expiry = now.addingTimeInterval(3600)
        AIStubURLProtocol.handler = { request, _ in
            if request.url?.path == F.signUpPath {
                return (200, [:], F.authReply(token: "token-1", refresh: "refresh-1", expiresAt: expiry))
            }
            return (200, [:], F.stepsReply)
        }

        let steps = try await client.breakDown(title: "Email landlord", currentStep: "")

        XCTAssertEqual(steps, ["Open Mail.", "Write one line."])
        let sent = AIStubURLProtocol.sent
        XCTAssertEqual(sent.map { $0.request.url?.path }, [F.signUpPath, F.functionPath])

        let signUp = sent[0]
        XCTAssertEqual(signUp.request.httpMethod, "POST")
        XCTAssertEqual(signUp.request.value(forHTTPHeaderField: "apikey"), "anon-key")
        XCTAssertEqual(signUp.request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(signUp.body, Data("{}".utf8))

        let call = sent[1]
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "Authorization"), "Bearer token-1")
        XCTAssertEqual(call.request.value(forHTTPHeaderField: "apikey"), "anon-key")
        let body = F.object(call.body)
        XCTAssertEqual(body["task"] as? String, "break_down")
        XCTAssertEqual((body["input"] as? [String: Any])?["title"] as? String, "Email landlord")

        XCTAssertEqual(store.stored?.accessToken, "token-1")
        XCTAssertEqual(store.stored?.refreshToken, "refresh-1")
        XCTAssertTrue(client.hasSession)
    }

    func testValidSessionIsReused() async throws {
        let store = AIMemorySessionStore(validSession())
        let client = makeClient(store: store)
        AIStubURLProtocol.handler = { _, _ in (200, [:], F.stepsReply) }

        _ = try await client.breakDown(title: "Email landlord", currentStep: "")

        XCTAssertEqual(AIStubURLProtocol.sent.map { $0.request.url?.path }, [F.functionPath])
        XCTAssertEqual(AIStubURLProtocol.sent.first?.request.value(forHTTPHeaderField: "Authorization"), "Bearer token-0")
    }

    func testExpiringSessionIsRefreshedFirst() async throws {
        var expiring = validSession()
        expiring.expiresAt = now.addingTimeInterval(30)
        let store = AIMemorySessionStore(expiring)
        let client = makeClient(store: store)
        let expiry = now.addingTimeInterval(3600)
        AIStubURLProtocol.handler = { request, _ in
            if request.url?.path == F.tokenPath {
                return (200, [:], F.authReply(token: "token-2", refresh: "refresh-2", expiresAt: expiry))
            }
            return (200, [:], F.stepsReply)
        }

        _ = try await client.breakDown(title: "Email landlord", currentStep: "")

        let sent = AIStubURLProtocol.sent
        XCTAssertEqual(sent.map { $0.request.url?.path }, [F.tokenPath, F.functionPath])
        XCTAssertEqual(sent[0].request.url?.query, "grant_type=refresh_token")
        XCTAssertEqual(F.object(sent[0].body)["refresh_token"] as? String, "refresh-0")
        XCTAssertEqual(sent[1].request.value(forHTTPHeaderField: "Authorization"), "Bearer token-2")
        XCTAssertEqual(store.stored?.refreshToken, "refresh-2")
    }

    func testRejectedTokenIsRefreshedOnce() async throws {
        let store = AIMemorySessionStore(validSession())
        let client = makeClient(store: store)
        let expiry = now.addingTimeInterval(3600)
        AIStubURLProtocol.handler = { request, _ in
            if request.url?.path == F.tokenPath {
                return (200, [:], F.authReply(token: "token-2", refresh: "refresh-2", expiresAt: expiry))
            }
            if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-0" {
                return (401, [:], F.unauthorizedReply)
            }
            return (200, [:], F.stepsReply)
        }

        let steps = try await client.breakDown(title: "Email landlord", currentStep: "")

        XCTAssertEqual(steps.count, 2)
        XCTAssertEqual(AIStubURLProtocol.sent.map { $0.request.url?.path }, [F.functionPath, F.tokenPath, F.functionPath])
        XCTAssertEqual(AIStubURLProtocol.count(path: F.signUpPath), 0)
    }

    func testStillRejectedTokenSignsInAgainOnce() async {
        let store = AIMemorySessionStore(validSession())
        let client = makeClient(store: store)
        let expiry = now.addingTimeInterval(3600)
        AIStubURLProtocol.handler = { request, _ in
            switch request.url?.path ?? "" {
            case F.tokenPath:
                return (200, [:], F.authReply(token: "token-2", refresh: "refresh-2", expiresAt: expiry))
            case F.signUpPath:
                return (200, [:], F.authReply(token: "token-3", refresh: "refresh-3", expiresAt: expiry))
            default:
                return (401, [:], F.unauthorizedReply)
            }
        }

        await expectError(.unauthorized) {
            _ = try await client.breakDown(title: "Email landlord", currentStep: "")
        }
        XCTAssertEqual(
            AIStubURLProtocol.sent.map { $0.request.url?.path },
            [F.functionPath, F.tokenPath, F.functionPath, F.signUpPath, F.functionPath]
        )
        XCTAssertEqual(AIStubURLProtocol.sent.last?.request.value(forHTTPHeaderField: "Authorization"), "Bearer token-3")
    }

    func testQuotaPausesCloudAI() async {
        let store = AIMemorySessionStore(validSession())
        let client = makeClient(store: store)
        AIStubURLProtocol.handler = { _, _ in
            (429, ["Retry-After": "3600"], F.json(#"{"ok": false, "error": "quota_exceeded", "message": "That’s all for today."}"#))
        }

        await expectError(.quotaExceeded(retryAfter: 3600)) {
            _ = try await client.breakDown(title: "Email landlord", currentStep: "")
        }
        XCTAssertTrue(client.isPaused)
        XCTAssertEqual(client.pausedUntil, now.addingTimeInterval(3600))

        await expectError(.paused) {
            _ = try await client.breakDown(title: "Email landlord", currentStep: "")
        }
        XCTAssertEqual(AIStubURLProtocol.count(path: F.functionPath), 1, "Paused calls never reach the network")
    }

    func testServerNotConfiguredPausesCloudAI() async {
        let client = makeClient(store: AIMemorySessionStore(validSession()))
        AIStubURLProtocol.handler = { _, _ in
            (503, [:], F.json(#"{"ok": false, "error": "not_configured", "message": "AI isn’t set up yet."}"#))
        }
        await expectError(.serviceUnavailable) {
            _ = try await client.breakDown(title: "Email landlord", currentStep: "")
        }
        XCTAssertTrue(client.isPaused)
    }

    func testNetworkFailureIsReported() async {
        let client = makeClient(store: AIMemorySessionStore(validSession()))
        AIStubURLProtocol.handler = { _, _ in throw URLError(.notConnectedToInternet) }
        await expectError(.network) {
            _ = try await client.breakDown(title: "Email landlord", currentStep: "")
        }
        XCTAssertFalse(client.isPaused)
    }

    func testUnconfiguredClientDoesNothing() async {
        let client = CloudAIClient(config: nil, store: AIMemorySessionStore())
        XCTAssertFalse(client.isConfigured)
        await expectError(.notConfigured) {
            _ = try await client.breakDown(title: "Email landlord", currentStep: "")
        }
        let deleted = try? await client.deleteCloudData()
        XCTAssertEqual(deleted, false)
    }

    // MARK: - Delete

    func testDeleteWithoutAnAccountSendsNothing() async throws {
        let client = makeClient(store: AIMemorySessionStore())
        let deleted = try await client.deleteCloudData()
        XCTAssertFalse(deleted)
        XCTAssertTrue(AIStubURLProtocol.sent.isEmpty)
    }

    func testDeleteRemovesServerDataAndForgetsTheSession() async throws {
        let store = AIMemorySessionStore(validSession())
        let client = makeClient(store: store)
        AIStubURLProtocol.handler = { _, _ in
            (200, [:], F.json(#"{"ok": true, "task": "delete_me", "result": {"deleted": true}}"#))
        }

        let deleted = try await client.deleteCloudData()

        XCTAssertTrue(deleted)
        XCTAssertNil(store.stored)
        XCTAssertFalse(client.hasSession)
        let sentBody = try XCTUnwrap(AIStubURLProtocol.sent.first?.body)
        let body = F.object(sentBody)
        XCTAssertEqual(body["task"] as? String, "delete_me")
        XCTAssertEqual((body["input"] as? [String: Any])?.count, 0)
    }

    func testDeleteForAnAccountTheServerNoLongerKnows() async throws {
        let store = AIMemorySessionStore(validSession())
        let client = makeClient(store: store)
        AIStubURLProtocol.handler = { request, _ in
            if request.url?.path == F.tokenPath {
                return (400, [:], F.json(#"{"error": "invalid_grant"}"#))
            }
            return (401, [:], F.unauthorizedReply)
        }

        let deleted = try await client.deleteCloudData()

        XCTAssertFalse(deleted)
        XCTAssertNil(store.stored)
        XCTAssertEqual(AIStubURLProtocol.count(path: F.signUpPath), 0, "Deleting never creates a new account")
    }
}
