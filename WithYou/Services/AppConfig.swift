//
//  AppConfig.swift
//  WithYou
//
//  Created by Codex on 2/10/26.
//

import Foundation

/// Build-time settings read from Info.plist (filled in from `Config/WithYou.xcconfig`).
enum AppConfig {
    /// `https://<project>.supabase.co` for optional cloud AI, or nil when it isn't set up.
    ///
    /// Info.plist holds the host only (`WITHYOU_SUPABASE_HOST`), because `//` starts a
    /// comment in xcconfig files.
    static let supabaseBaseURL: URL? = supabaseURL(fromHost: infoValue("WITHYOU_SUPABASE_HOST"))

    /// The Supabase publishable (anon) key, or nil when it isn't set up.
    static let supabaseAnonKey: String? = infoValue("WITHYOU_SUPABASE_ANON_KEY")

    /// `https://<host>` from a configured host, or nil for anything unusable.
    static func supabaseURL(fromHost raw: String?) -> URL? {
        guard let raw = cleanedValue(raw) else { return nil }
        return normalizedURL(from: raw)
    }

    /// A configured value without surrounding quotes or whitespace. Nil when it is empty or
    /// still an unresolved build setting such as `$(WITHYOU_SUPABASE_HOST)`.
    static func cleanedValue(_ raw: String?) -> String? {
        guard let raw else { return nil }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2)
            || (trimmed.hasPrefix("'") && trimmed.hasSuffix("'") && trimmed.count >= 2) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            return nil
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func infoValue(_ key: String) -> String? {
        cleanedValue(Bundle.main.object(forInfoDictionaryKey: key) as? String)
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
