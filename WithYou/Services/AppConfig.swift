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
        return Secrets.apiKey
    }()

    private static func infoValue(_ key: String) -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\""))
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            return nil
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let lower = trimmed.lowercased()

        // xcconfig treats // as comment, so "https://host" can collapse to "https:".
        if lower == "https:" || lower == "http:" {
            return nil
        }

        let withScheme: String
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            withScheme = trimmed
        } else {
            withScheme = "https://\(trimmed)"
        }

        guard let url = URL(string: withScheme), url.host != nil else {
            return nil
        }

        if let host = url.host?.lowercased(), host == "https" || host == "http" {
            return nil
        }
        return url
    }
}
