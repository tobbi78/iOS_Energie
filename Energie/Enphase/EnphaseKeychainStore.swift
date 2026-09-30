//
//  EnphaseKeychainStore.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import Security

/// Keys for the individual secrets persisted by `EnphaseSecretStoring`.
enum EnphaseSecretKey: String, CaseIterable {
    case clientID
    case clientSecret
    case apiKey
    case accessToken
    case refreshToken
    case tokenExpiresAt
    case systemID
}

/// Storage abstraction for Enphase secrets, injectable so tests never touch the real Keychain.
protocol EnphaseSecretStoring: Sendable {
    func read(_ key: EnphaseSecretKey) -> String?
    func write(_ key: EnphaseSecretKey, value: String?)
}

/// Local (device-only, not iCloud-synchronized) Keychain-backed secret store.
///
/// Intentionally local-only: cloud sync of secrets (iCloud Keychain) was planned but deferred
/// together with the rest of the CloudKit-based architecture (see BACKLOG.md, "Nicht umsetzbar
/// ohne kostenpflichtigen Apple Developer Account").
struct EnphaseKeychainStore: EnphaseSecretStoring {
    private let service: String

    init(service: String = "de.florian.tobias.Energie.enphase") {
        self.service = service
    }

    func read(_ key: EnphaseSecretKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: EnphaseSecretKey, value: String?) {
        let query = baseQuery(for: key)

        guard let value, let data = value.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }

        let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    private func baseQuery(for key: EnphaseSecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
    }
}

/// In-memory stand-in for tests and SwiftUI previews.
final class InMemoryEnphaseSecretStore: EnphaseSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [EnphaseSecretKey: String] = [:]

    init(seed: [EnphaseSecretKey: String] = [:]) {
        storage = seed
    }

    func read(_ key: EnphaseSecretKey) -> String? {
        lock.withLock { storage[key] }
    }

    func write(_ key: EnphaseSecretKey, value: String?) {
        lock.withLock { storage[key] = value }
    }
}
