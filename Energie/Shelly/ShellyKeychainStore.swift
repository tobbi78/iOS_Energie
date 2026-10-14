//
//  ShellyKeychainStore.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Security

/// Keys for the individual secrets persisted by `ShellySecretStoring`.
enum ShellySecretKey: String, CaseIterable {
    case serverURI
    case authKey

    /// Whether this item syncs across the user's devices via iCloud Keychain (same model as
    /// `EnphaseSecretKey.isSynchronizable`, see `EnphaseKeychainStore.swift`): the `authKey`
    /// grants direct, immediate access to the user's devices (soon including switching them,
    /// Epic 13) with no refresh-token mechanism to fall back on (F11.4), so it stays
    /// device-local. The server URI is not a secret (it's shown in plain text in the Shelly app
    /// alongside the key) and syncs for cross-device convenience.
    var isSynchronizable: Bool {
        switch self {
        case .serverURI:
            return true
        case .authKey:
            return false
        }
    }
}

/// Storage abstraction for Shelly secrets, injectable so tests never touch the real Keychain.
protocol ShellySecretStoring: Sendable {
    func read(_ key: ShellySecretKey) -> String?
    func write(_ key: ShellySecretKey, value: String?)
}

/// Keychain-backed secret store for the Shelly Cloud Control API credentials (F11.2). Mirrors
/// `EnphaseKeychainStore`'s partially-synchronized approach: the server URI syncs across the
/// user's devices via iCloud Keychain, the `authKey` stays device-local.
struct ShellyKeychainStore: ShellySecretStoring {
    private let service: String

    init(service: String = "de.florian.tobias.Energie.shelly") {
        self.service = service
    }

    func read(_ key: ShellySecretKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: ShellySecretKey, value: String?) {
        let query = baseQuery(for: key)

        guard let value, let data = value.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }

        // Same accessibility choice as EnphaseKeychainStore: AfterFirstUnlock keeps the item
        // readable by background work (e.g. a future Shelly widget poll) once the device has
        // been unlocked since boot. The plain (non-"ThisDeviceOnly") variant is required for the
        // synchronizable key, since Apple's Keychain API rejects combining "ThisDeviceOnly" with
        // kSecAttrSynchronizable.
        let accessible = key.isSynchronizable
            ? kSecAttrAccessibleAfterFirstUnlock
            : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = accessible
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    /// See `EnphaseKeychainStore.baseQuery(for:)` for why `kSecAttrSynchronizable` has to be part
    /// of every query consistently.
    private func baseQuery(for key: ShellySecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: key.isSynchronizable,
        ]
    }
}

/// In-memory stand-in for tests and SwiftUI previews.
final class InMemoryShellySecretStore: ShellySecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ShellySecretKey: String] = [:]

    init(seed: [ShellySecretKey: String] = [:]) {
        storage = seed
    }

    func read(_ key: ShellySecretKey) -> String? {
        lock.withLock { storage[key] }
    }

    func write(_ key: ShellySecretKey, value: String?) {
        lock.withLock { storage[key] = value }
    }
}
