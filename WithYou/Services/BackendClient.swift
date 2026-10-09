//
//  BackendClient.swift
//  WithYou
//
//  Created by Codex on 2/9/26.
//

import Foundation

struct DeviceRegisterPayload: Encodable {
    let install_id: String
    let device_token: String
    let timezone: String
    let push_enabled: Bool
    let apns_environment: String?
}

/// `POST /v1/devices/register` → `{"ok": true, "install_has_secret": true, "install_secret": "<string>"}`.
/// `install_secret` is only present when the server issues a new one. Older servers send neither field.
private struct DeviceRegisterResponse: Decodable {
    let ok: Bool?
    let install_secret: String?
    let install_has_secret: Bool?
}

/// What a registration told us about this install's secret.
struct DeviceRegisterResult {
    /// A newly issued secret, if the server sent one.
    let newSecret: String?
    /// True when the server says this install already has a secret (even if it didn't send it).
    let serverHasSecret: Bool
}

enum BackendClient {
    static let baseURL = AppConfig.apiBaseURL

    private static let requestTimeout: TimeInterval = 20

    enum HTTPError: Error, LocalizedError {
        case status(Int, String)

        var errorDescription: String? {
            switch self {
            case let .status(code, body):
                return "HTTP \(code): \(body)"
            }
        }
    }

    // MARK: - Devices

    /// Registers (or refreshes) this install's push token.
    ///
    /// - Parameter installSecret: the secret from an earlier registration, sent as
    ///   `X-Install-Secret` so the server knows this install owns the record.
    /// - Returns: a newly issued install secret (if any) and whether the server holds one.
    @discardableResult
    static func registerDevice(_ payload: DeviceRegisterPayload, installSecret: String? = nil) async throws -> DeviceRegisterResult {
        let url = baseURL.appendingPathComponent("/v1/devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request, installSecret: installSecret)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw HTTPError.status(http.statusCode, body)
        }

        // A body we can't read is not a failure: the device is registered either way.
        guard let decoded = try? JSONDecoder().decode(DeviceRegisterResponse.self, from: data) else {
            return DeviceRegisterResult(newSecret: nil, serverHasSecret: false)
        }
        let secret = decoded.install_secret?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DeviceRegisterResult(
            newSecret: (secret?.isEmpty ?? true) ? nil : secret,
            serverHasSecret: decoded.install_has_secret ?? false
        )
    }

    // MARK: - Installs

    /// Deletes everything the server keeps for this install (`DELETE /v1/installs/{install_id}`).
    /// A 404 means there is nothing to delete, which counts as success.
    static func deleteInstall(installId: String, secret: String?) async throws {
        let url = baseURL
            .appendingPathComponent("/v1/installs")
            .appendingPathComponent(installId)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = requestTimeout
        applyAuthHeaders(to: &request, installSecret: secret)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if http.statusCode == 404 {
            return
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw HTTPError.status(http.statusCode, body)
        }
    }

    // MARK: - Helpers

    private static func applyAuthHeaders(to request: inout URLRequest, installSecret: String?) {
        if let apiKey = AppConfig.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        if let installSecret, !installSecret.isEmpty {
            request.setValue(installSecret, forHTTPHeaderField: "X-Install-Secret")
        }
    }
}
