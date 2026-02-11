//
//  AppConfig.swift
//  WithYou
//
//  Created by Codex on 2/10/26.
//

import Foundation

enum AppConfig {
    static let apiBaseURL: URL = {
        if let raw = infoValue("WITHYOU_API_BASE_URL"),
           let url = normalizedURL(from: raw) {
            return url
        }
        return URL(string: "https://withyou-backend.fly.dev")!
    }()

    static let apiKey: String? = {
        infoValue("WITHYOU_API_KEY")
    }()

    private static func infoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme: String
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard let url = URL(string: withScheme), url.host != nil else {
            return nil
        }
        return url
    }
}
