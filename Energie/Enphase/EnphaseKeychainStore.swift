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
    case operationalAt
}

/// Storage abstraction for Enphase secrets, injectable so tests never touch the real Keychain.
protocol EnphaseSecretStoring: Sendable {
    func read(_ key: EnphaseSecretKey) -> String?
    func write(_ key: EnphaseSecretKey, value: String?)
}

/// iCloud-Keychain-synchronized secret store (Epic 0, F0.3) — one sign-in on any of the user's
/// devices carries over to the others, instead of each device needing its own independent OAuth
/// session. Was local-only until the paid Apple Developer account made synchronizable Keychain
/// items possible (see BACKLOG.md, "Nicht umsetzbar ohne kostenpflichtigen Apple Developer
/// Account"). The widget extension's own duplicated Keychain code (`PVWidgetKeychain` in
/// `PVWidgetDataSource.swift`) must stay in sync with the `kSecAttrSynchronizable`/
/// `kSecAttrAccessible` choices here, or it'll stop finding what this type writes.
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

        // Without an explicit kSecAttrAccessible, items default to kSecAttrAccessibleWhenUnlocked
        // — inaccessible to background processes (like the widget extension's periodic timeline
        // refresh) whenever the device is locked, which is routinely the case. AfterFirstUnlock
        // keeps it readable in the background once the device has been unlocked at least once
        // since boot. **Not** the "ThisDeviceOnly" variant (F0.3): Apple's Keychain API rejects
        // combining any "ThisDeviceOnly" accessibility with `kSecAttrSynchronizable` — the two are
        // mutually exclusive by design, since ThisDeviceOnly explicitly means "never migrate".
        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var newItem = query
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(newItem as CFDictionary, nil)
        }
    }

    /// `kSecAttrSynchronizable: true` (F0.3) makes queries search the iCloud-synced item class —
    /// without it, `SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete` only ever see
    /// *non*-synchronizable items, so this one flag has to be consistent across read, update, add,
    /// and delete, which is why it lives here once instead of being repeated at each call site.
    /// **Side effect:** a login stored before this change was non-synchronizable and becomes
    /// invisible to this query — same one-time re-login already documented for the App Group
    /// keychain-access-groups change (see BACKLOG.md F5.6).
    private func baseQuery(for key: EnphaseSecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: true,
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
