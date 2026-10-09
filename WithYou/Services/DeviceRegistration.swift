//
//  DeviceRegistration.swift
//  WithYou
//
//  Created by Codex on 2/9/26.
//

import Foundation
import UserNotifications
import OSLog

/// Keeps the backend's copy of this install (push token, timezone, permission) up to date,
/// and lets the person turn that sharing off, which deletes the server record.
enum DeviceRegistration {
    private actor RegistrationGate {
        private var inFlight = false

        func begin() -> Bool {
            guard !inFlight else { return false }
            inFlight = true
            return true
        }

        func end() {
            inFlight = false
        }
    }

    private static let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "push")
    private static let gate = RegistrationGate()

    private static let tokenKey = "withyou.apns_token"
    private static let lastSentSignatureKey = "withyou.apns_last_sent_signature"
    private static let lastFailureSignatureKey = "withyou.apns_last_failure_signature"
    private static let lastFailureAtKey = "withyou.apns_last_failure_at"
    private static let serverSharingEnabledKey = "withyou.server_sharing_enabled"

    // MARK: - Token cache

    static func storeToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    static func cachedToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    // MARK: - Server sharing

    /// Whether this install may send its push token and timezone to the WithYou server.
    /// On by default (needed for server-sent reminders); the person can turn it off in Profiles.
    static var isServerSharingEnabled: Bool {
        UserDefaults.standard.object(forKey: serverSharingEnabledKey) as? Bool ?? true
    }

    /// Turns server sharing on or off.
    ///
    /// - Off: asks the server to delete this install's data first. If that fails (anything
    ///   other than "not found"), the setting stays as it was and the error is thrown.
    ///   On success, the local registration state and install secret are cleared.
    /// - On: re-enables sharing and re-registers right away if we already have a push token.
    static func setServerSharingEnabled(_ enabled: Bool) async throws {
        let defaults = UserDefaults.standard

        if enabled {
            defaults.set(true, forKey: serverSharingEnabledKey)
            if let token = cachedToken() {
                await registerIfNeeded(token: token, force: true)
            }
            return
        }

        // Block new registrations while the delete is in flight; restored below if it fails.
        let previous = isServerSharingEnabled
        defaults.set(false, forKey: serverSharingEnabledKey)

        let installId = InstallID.get()
        let secretAccount = KeychainStore.installSecretAccount(for: installId)
        let secret = KeychainStore.get(account: secretAccount)

        do {
            try await withRetry("Install delete") {
                try await BackendClient.deleteInstall(installId: installId, secret: secret)
            }
        } catch {
            defaults.set(previous, forKey: serverSharingEnabledKey)
            log.error("Could not delete install data on the server: \(String(describing: error), privacy: .public)")
            throw error
        }

        defaults.removeObject(forKey: lastSentSignatureKey)
        defaults.removeObject(forKey: lastFailureSignatureKey)
        defaults.removeObject(forKey: lastFailureAtKey)
        KeychainStore.delete(account: secretAccount)
        log.info("Server sharing turned off; install data deleted")
    }

    // MARK: - Registration

    static func registerIfNeeded(token: String, force: Bool = false) async {
        guard isServerSharingEnabled else {
            log.info("Server sharing is off; skipping device registration")
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let pushEnabled = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        let timezone = TimeZone.current.identifier

        #if DEBUG
        let apnsEnvironment = "sandbox"
        #else
        let apnsEnvironment = "production"
        #endif

        let installId = InstallID.get()
        let secretAccount = KeychainStore.installSecretAccount(for: installId)
        let existingSecret = KeychainStore.get(account: secretAccount)

        // Including whether we hold a secret means installs registered before secrets
        // existed register once more and receive one.
        let signature = makeSignature(
            token: token,
            pushEnabled: pushEnabled,
            timezone: timezone,
            apnsEnvironment: apnsEnvironment,
            hasSecret: existingSecret != nil
        )
        let lastSignature = UserDefaults.standard.string(forKey: lastSentSignatureKey)
        if !force, signature == lastSignature {
            log.info("Device registration unchanged; skipping")
            return
        }
        if !force, shouldDelayRetry(for: signature) {
            log.info("Recent device registration failure; delaying retry")
            return
        }

        guard await gate.begin() else {
            log.info("Device registration already in progress; skipping duplicate")
            return
        }
        defer {
            Task { await gate.end() }
        }

        let payload = DeviceRegisterPayload(
            install_id: installId,
            device_token: token,
            timezone: timezone,
            push_enabled: pushEnabled,
            apns_environment: apnsEnvironment
        )

        do {
            var registeredId = installId
            var account = secretAccount
            var result = try await withRetry("Device register") {
                try await BackendClient.registerDevice(payload, installSecret: existingSecret)
            }

            // The server holds a secret for this install that we never received (it was issued
            // to an older app build that didn't keep it) and it never re-issues one. Start over
            // with a fresh install ID so this device gets its own secret. The device token moves
            // to the new install on the server; the old install record is left with no devices.
            if existingSecret == nil, result.newSecret == nil, result.serverHasSecret {
                let freshId = InstallID.reset()
                let freshPayload = DeviceRegisterPayload(
                    install_id: freshId,
                    device_token: token,
                    timezone: timezone,
                    push_enabled: pushEnabled,
                    apns_environment: apnsEnvironment
                )
                result = try await withRetry("Device register (fresh install ID)") {
                    try await BackendClient.registerDevice(freshPayload, installSecret: nil)
                }
                registeredId = freshId
                account = KeychainStore.installSecretAccount(for: freshId)
                log.info("Started a fresh install ID so this device gets its own secret")
            }

            // Sharing was turned off while this request was in flight: undo it quietly.
            guard isServerSharingEnabled else {
                log.info("Server sharing turned off during registration; removing the record again")
                try? await BackendClient.deleteInstall(
                    installId: registeredId,
                    secret: result.newSecret ?? KeychainStore.get(account: account)
                )
                KeychainStore.delete(account: account)
                return
            }

            if let newSecret = result.newSecret {
                KeychainStore.set(newSecret, account: account)
            }

            let sentSignature = makeSignature(
                token: token,
                pushEnabled: pushEnabled,
                timezone: timezone,
                apnsEnvironment: apnsEnvironment,
                hasSecret: KeychainStore.get(account: account) != nil
            )
            UserDefaults.standard.set(sentSignature, forKey: lastSentSignatureKey)
            UserDefaults.standard.removeObject(forKey: lastFailureSignatureKey)
            UserDefaults.standard.removeObject(forKey: lastFailureAtKey)
            log.info("Device registered with backend")
        } catch {
            recordFailure(for: signature)
            log.error("Failed to register device with backend: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Helpers

    private static func makeSignature(
        token: String,
        pushEnabled: Bool,
        timezone: String,
        apnsEnvironment: String,
        hasSecret: Bool
    ) -> String {
        "\(token)|\(pushEnabled)|\(timezone)|\(apnsEnvironment)|secret:\(hasSecret)"
    }

    /// Up to three attempts with short backoff, for errors that are likely temporary.
    private static func withRetry<T>(_ label: String, _ operation: () async throws -> T) async throws -> T {
        let delays: [UInt64] = [500_000_000, 1_500_000_000] // 0.5s, 1.5s between attempts
        var attempt = 0

        while true {
            do {
                return try await operation()
            } catch {
                guard isRetryable(error), attempt < delays.count else {
                    throw error
                }
                let attemptNumber = attempt + 1
                let delay = delays[attempt]
                log.error("\(label, privacy: .public) failed (attempt \(attemptNumber)), retrying: \(String(describing: error), privacy: .public)")
                try? await Task.sleep(nanoseconds: delay)
                attempt += 1
            }
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let httpError = error as? BackendClient.HTTPError {
            switch httpError {
            case let .status(code, _):
                return code == 429 || code >= 500
            }
        }
        if let urlError = error as? URLError {
            return urlError.code == .timedOut
                || urlError.code == .cannotFindHost
                || urlError.code == .cannotConnectToHost
                || urlError.code == .networkConnectionLost
                || urlError.code == .notConnectedToInternet
                || urlError.code == .dnsLookupFailed
        }
        return false
    }

    private static func shouldDelayRetry(for signature: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: lastFailureSignatureKey) == signature else { return false }
        guard let last = defaults.object(forKey: lastFailureAtKey) as? Date else { return false }
        return Date().timeIntervalSince(last) < 60
    }

    private static func recordFailure(for signature: String) {
        let defaults = UserDefaults.standard
        defaults.set(signature, forKey: lastFailureSignatureKey)
        defaults.set(Date(), forKey: lastFailureAtKey)
    }
}
