//
//  KeychainStore.swift
//  WithYou
//

import Foundation
import Security
import OSLog

/// Small wrapper around generic-password Keychain items for this app.
///
/// Holds the anonymous cloud AI session (see `KeychainCloudAISessionStore`), so tokens are
/// never kept in plain `UserDefaults`. `installSecretAccount(for:)` names the old server's
/// per-install secret so it can still be found and removed.
enum KeychainStore {
    static let service = "com.commongenelabs.WithYou"

    private static let log = Logger(subsystem: "com.commongenelabs.WithYou", category: "keychain")

    /// Keychain account name for an install's backend secret.
    static func installSecretAccount(for installId: String) -> String {
        "install_secret.\(installId)"
    }

    // MARK: - Read

    static func get(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                log.error("Keychain read failed: \(status, privacy: .public)")
            }
            return nil
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    // MARK: - Write

    /// Stores `value`, replacing any existing item for `account`.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else {
            log.error("Keychain update failed: \(updateStatus, privacy: .public)")
            return false
        }

        var addQuery = query
        for (key, value) in attributes {
            addQuery[key] = value
        }
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            log.error("Keychain add failed: \(addStatus, privacy: .public)")
            return false
        }
        return true
    }

    // MARK: - Delete

    /// Removes the item for `account`. Returns true if it is gone (including when it never existed).
    @discardableResult
    static func delete(account: String) -> Bool {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status == errSecSuccess || status == errSecItemNotFound {
            return true
        }
        log.error("Keychain delete failed: \(status, privacy: .public)")
        return false
    }

    // MARK: - Helpers

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
