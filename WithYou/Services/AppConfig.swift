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
           let url = URL(string: raw) {
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
}
