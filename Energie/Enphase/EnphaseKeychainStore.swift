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

    /// Whether this item syncs across the user's devices via iCloud Keychain, or stays
    /// device-local (F9.3 mitigation, 2026-10-05 security review, BACKLOG.md Epic 9): the OAuth
    /// tokens are what actually grants live API access, so a compromised iCloud account should
    /// not hand that access over on every device — only the long-lived app credentials (useless
    /// without a token or a fresh sign-in) and non-secret system metadata still sync for
    /// cross-device convenience. Each device now needs its own independent sign-in, same as
    /// before F0.3.
    var isSynchronizable: Bool {
        switch self {
        case .clientID, .clientSecret, .apiKey, .systemID, .operationalAt:
            return true
        case .accessToken, .refreshToken, .tokenExpiresAt:
            return false
        }
    }
}

/// Storage abstraction for Enphase secrets, injectable so tests never touch the real Keychain.
protocol EnphaseSecretStoring: Sendable {
    func read(_ key: EnphaseSecretKey) -> String?
    func write(_ key: EnphaseSecretKey, value: String?)
}

/// Partially iCloud-Keychain-synchronized secret store (Epic 0, F0.3; narrowed by F9.3): app
/// credentials and non-secret system metadata sync across the user's devices, so entering them
/// once is enough everywhere — but OAuth tokens (`EnphaseSecretKey.isSynchronizable`) are
/// device-local, so each device still needs its own independent sign-in. Was entirely local-only
/// until the paid Apple Developer account made synchronizable Keychain items possible (see
/// BACKLOG.md, "Nicht umsetzbar ohne kostenpflichtigen Apple Developer Account"), then entirely
/// synchronized until the 2026-10-05 security review found that too broad (BACKLOG.md F9.3). The
/// widget extension's own duplicated Keychain code (`PVWidgetKeychain` in
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
        // since boot. The plain (non-"ThisDeviceOnly") variant is required for synchronizable
        // keys (F0.3): Apple's Keychain API rejects combining any "ThisDeviceOnly" accessibility
        // with `kSecAttrSynchronizable: true` — the two are mutually exclusive by design, since
        // ThisDeviceOnly explicitly means "never migrate". Device-local keys (F9.3) use the
        // "ThisDeviceOnly" variant instead, which keeps the same background-availability
        // characteristics while opting out of iCloud sync.
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

    /// `kSecAttrSynchronizable` (per-key via `EnphaseSecretKey.isSynchronizable`, F0.3/F9.3)
    /// restricts queries to either the iCloud-synced or the device-local item class — without it
    /// matching explicitly, `SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete` only ever see
    /// *non*-synchronizable items, so this one flag has to be consistent across read, update, add,
    /// and delete, which is why it lives here once instead of being repeated at each call site.
    /// **Side effect:** an item stored under the other synchronizable value becomes invisible to
    /// this query — same one-time re-login already documented for the App Group
    /// keychain-access-groups change (see BACKLOG.md F5.6); tokens moving from synchronizable to
    /// device-local (F9.3) means every device needs one fresh sign-in after this change ships.
    private func baseQuery(for key: EnphaseSecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: key.isSynchronizable,
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
