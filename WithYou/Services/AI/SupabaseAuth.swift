//
//  SupabaseAuth.swift
//  WithYou
//
//  An anonymous Supabase account for cloud AI: a random id, no email, no name.
//  It is created the first time the person uses cloud AI and kept in the Keychain.
//

import Foundation

/// Where cloud AI talks to: the Supabase project URL and its publishable (anon) key.
nonisolated struct CloudAIConfig: Equatable {
    var baseURL: URL
    var anonKey: String

    var functionURL: URL { baseURL.appendingPathComponent("functions/v1/ai") }
    var signUpURL: URL { baseURL.appendingPathComponent("auth/v1/signup") }

    var refreshURL: URL {
        let tokenURL = baseURL.appendingPathComponent("auth/v1/token")
        var components = URLComponents(url: tokenURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        return components?.url ?? tokenURL
    }
}

extension CloudAIConfig {
    /// From Info.plist, or nil when this build has no Supabase project.
    @MainActor
    static var fromAppConfig: CloudAIConfig? {
        guard let baseURL = AppConfig.supabaseBaseURL, let anonKey = AppConfig.supabaseAnonKey else {
            return nil
        }
        return CloudAIConfig(baseURL: baseURL, anonKey: anonKey)
    }
}

/// A signed-in anonymous session.
nonisolated struct SupabaseSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userId: String
}

/// `POST /auth/v1/signup` and `POST /auth/v1/token?grant_type=refresh_token` both answer with this.
nonisolated struct SupabaseAuthResponse: Decodable {
    nonisolated struct User: Decodable {
        let id: String
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: Double?
    let expiresAt: Double?
    let user: User?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }

    /// The session to keep. `expires_at` (Unix seconds) wins; otherwise `expires_in` from `now`.
    func session(now: Date, previousUserId: String? = nil) -> SupabaseSession {
        let expiry: Date
        if let expiresAt {
            expiry = Date(timeIntervalSince1970: expiresAt)
        } else {
            expiry = now.addingTimeInterval(expiresIn ?? 3600)
        }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: expiry,
            userId: user?.id ?? previousUserId ?? ""
        )
    }
}

// MARK: - Session storage

@MainActor
protocol CloudAISessionStore: AnyObject {
    func load() -> SupabaseSession?
    func save(_ session: SupabaseSession)
    func clear()
}

/// Keeps the session in the Keychain (this device only, available after first unlock).
final class KeychainCloudAISessionStore: CloudAISessionStore {
    static let account = "cloud_ai.supabase_session"

    func load() -> SupabaseSession? {
        guard let json = KeychainStore.get(account: Self.account) else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: Data(json.utf8))
    }

    func save(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session),
              let json = String(data: data, encoding: .utf8) else { return }
        KeychainStore.set(json, account: Self.account)
    }

    func clear() {
        KeychainStore.delete(account: Self.account)
    }
}

// MARK: - Auth

/// Signs in anonymously, keeps the token fresh, and recovers once from a rejected token.
///
/// Requests that arrive together share one sign-in or refresh, so a burst of calls never
/// creates two accounts.
final class SupabaseAuth {
    /// Refresh when fewer than this many seconds are left on the access token.
    static let refreshMargin: TimeInterval = 60
    private static let requestTimeout: TimeInterval = 15

    private let config: CloudAIConfig
    private let urlSession: URLSession
    private let store: CloudAISessionStore
    private let now: () -> Date

    private var cached: SupabaseSession?
    private var didLoad = false
    private var pendingSignIn: Task<SupabaseSession, Error>?
    private var pendingRefresh: Task<SupabaseSession, Error>?

    init(
        config: CloudAIConfig,
        urlSession: URLSession = .shared,
        store: CloudAISessionStore? = nil,
        now: @escaping () -> Date = { Date() }
    ) {
        self.config = config
        self.urlSession = urlSession
        // Built here rather than as a default argument: default arguments are evaluated outside
        // the main actor, and the Keychain store is main-actor isolated.
        self.store = store ?? KeychainCloudAISessionStore()
        self.now = now
    }

    /// The stored session, if this install has signed in before.
    var session: SupabaseSession? {
        if !didLoad {
            cached = store.load()
            didLoad = true
        }
        return cached
    }

    /// A usable access token: the current one, a refreshed one when it is about to expire,
    /// or (when `signInIfNeeded`) a new anonymous sign-in.
    func accessToken(signInIfNeeded: Bool = true) async throws -> String {
        if let session {
            if session.expiresAt.timeIntervalSince(now()) > Self.refreshMargin {
                return session.accessToken
            }
            do {
                return try await refresh().accessToken
            } catch CloudAIError.network {
                throw CloudAIError.network
            } catch {
                // The refresh token was rejected; fall through to a new sign-in.
            }
        }
        guard signInIfNeeded else { throw CloudAIError.unauthorized }
        return try await signIn().accessToken
    }

    /// Exchanges the refresh token for a new session.
    func refresh() async throws -> SupabaseSession {
        if let pendingRefresh {
            return try await pendingRefresh.value
        }
        guard let current = session else { throw CloudAIError.unauthorized }

        let task = Task { () async throws -> SupabaseSession in
            let body = try JSONEncoder().encode(["refresh_token": current.refreshToken])
            let response = try await self.authRequest(url: self.config.refreshURL, body: body)
            return response.session(now: self.now(), previousUserId: current.userId)
        }
        pendingRefresh = task
        defer { pendingRefresh = nil }

        let refreshed = try await task.value
        keep(refreshed)
        return refreshed
    }

    /// Creates a new anonymous account and keeps its session.
    func signIn() async throws -> SupabaseSession {
        if let pendingSignIn {
            return try await pendingSignIn.value
        }
        let task = Task { () async throws -> SupabaseSession in
            let response = try await self.authRequest(url: self.config.signUpURL, body: Data("{}".utf8))
            return response.session(now: self.now())
        }
        pendingSignIn = task
        defer { pendingSignIn = nil }

        let session = try await task.value
        keep(session)
        return session
    }

    /// Forgets the session on this device (the server account is untouched).
    func signOutLocally() {
        cached = nil
        didLoad = true
        store.clear()
    }

    private func keep(_ session: SupabaseSession) {
        cached = session
        didLoad = true
        store.save(session)
    }

    // MARK: - Requests

    static func authRequest(url: URL, anonKey: String, body: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func authRequest(url: URL, body: Data) async throws -> SupabaseAuthResponse {
        let request = Self.authRequest(url: url, anonKey: config.anonKey, body: body)
        let result: (Data, URLResponse)
        do {
            result = try await urlSession.data(for: request)
        } catch {
            throw CloudAIError.network
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw CloudAIError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            switch http.statusCode {
            case 400, 401, 403, 404, 422:
                throw CloudAIError.unauthorized
            case 429:
                throw CloudAIError.quotaExceeded(retryAfter: CloudAIClient.retryAfter(from: http))
            default:
                throw CloudAIError.server(status: http.statusCode)
            }
        }
        do {
            return try JSONDecoder().decode(SupabaseAuthResponse.self, from: data)
        } catch {
            throw CloudAIError.invalidResponse
        }
    }
}
