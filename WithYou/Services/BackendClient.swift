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

enum BackendClient {
    static let baseURL = AppConfig.apiBaseURL
    
    enum HTTPError: Error, LocalizedError {
        case status(Int, String)
        
        var errorDescription: String? {
            switch self {
            case let .status(code, body):
                return "HTTP \(code): \(body)"
            }
        }
    }

    static func registerDevice(_ payload: DeviceRegisterPayload) async throws {
        let url = baseURL.appendingPathComponent("/v1/devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = AppConfig.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw HTTPError.status(http.statusCode, body)
        }
    }
}
