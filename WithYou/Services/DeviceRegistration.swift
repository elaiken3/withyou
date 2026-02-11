//
//  DeviceRegistration.swift
//  WithYou
//
//  Created by Codex on 2/9/26.
//

import Foundation
import UserNotifications
import OSLog

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

    static func storeToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: tokenKey)
    }

    static func cachedToken() -> String? {
        UserDefaults.standard.string(forKey: tokenKey)
    }

    static func registerIfNeeded(token: String, force: Bool = false) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let pushEnabled = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let timezone = TimeZone.current.identifier

        #if DEBUG
        let apnsEnvironment = "sandbox"
        #else
        let apnsEnvironment = "production"
        #endif

        let signature = "\(token)|\(pushEnabled)|\(timezone)|\(apnsEnvironment)"
        let lastSignature = UserDefaults.standard.string(forKey: lastSentSignatureKey)
        if !force, signature == lastSignature {
            log.info("ℹ️ Device registration unchanged; skipping")
            return
        }
        
        guard await gate.begin() else {
            log.info("ℹ️ Device registration already in progress; skipping duplicate")
            return
        }
        defer {
            Task { await gate.end() }
        }

        let payload = DeviceRegisterPayload(
            install_id: InstallID.get(),
            device_token: token,
            timezone: timezone,
            push_enabled: pushEnabled,
            apns_environment: apnsEnvironment
        )

        do {
            try await registerWithRetry(payload)
            UserDefaults.standard.set(signature, forKey: lastSentSignatureKey)
            log.info("✅ Device registered with backend")
        } catch {
            log.error("❌ Failed to register device with backend: \(String(describing: error), privacy: .public)")
        }
    }

    private static func registerWithRetry(_ payload: DeviceRegisterPayload) async throws {
        let delays: [UInt64] = [500_000_000, 1_500_000_000, 3_000_000_000] // 0.5s, 1.5s, 3s

        var lastError: Error?
        for (idx, delay) in delays.enumerated() {
            do {
                try await BackendClient.registerDevice(payload)
                return
            } catch {
                lastError = error
                if !isRetryable(error) {
                    throw error
                }
                log.error("⚠️ Device register failed (attempt \(idx + 1), retrying): \(String(describing: error), privacy: .public)")
                try? await Task.sleep(nanoseconds: delay)
            }
        }

        if let lastError {
            throw lastError
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
}
