//
//  InstallID.swift
//  WithYou
//
//  Created by Codex on 2/9/26.
//

import Foundation

enum InstallID {
    private static let key = "withyou.install_id"

    static func get() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: key)
        return fresh
    }

    /// Replaces the install ID with a fresh one and returns it. Used when the server
    /// holds a secret for the old ID that this device never received.
    @discardableResult
    static func reset() -> String {
        let fresh = UUID().uuidString.lowercased()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }
}
