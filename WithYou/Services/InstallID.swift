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
}
