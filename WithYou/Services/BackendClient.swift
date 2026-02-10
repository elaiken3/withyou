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
    static let baseURL = URL(string: "https://withyou-backend.fly.dev")!

    static func registerDevice(_ payload: DeviceRegisterPayload) async throws {
        let url = baseURL.appendingPathComponent("/v1/devices/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}
