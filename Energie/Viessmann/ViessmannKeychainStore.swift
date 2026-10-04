//
//  ViessmannKeychainStore.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation
import Security

/// Keys for the individual secrets persisted by `ViessmannSecretStoring`. Simpler than Enphase's
/// (see `EnphaseSecretKey`): PKCE replaces the client secret/API key, and the installation/
/// gateway/device IDs resolve the "wrong device" gotcha documented in
/// Plans/Waermepumpe-Integration.md (Abschnitt 3) — the gateway itself can appear as a
/// pseudo-device and must not be polled for heating data.
enum ViessmannSecretKey: String, CaseIterable {
    case clientID
    case accessToken
    case refreshToken
    case tokenExpiresAt
    case installationID
    case gatewaySerial
    case deviceID
}

/// Storage abstraction for Viessmann secrets, injectable so tests never touch the real Keychain.
protocol ViessmannSecretStoring: Sendable {
    func read(_ key: ViessmannSecretKey) -> String?
    func write(_ key: ViessmannSecretKey, value: String?)
}

/// iCloud-Keychain-synchronized secret store (Epic 0, F0.3) — same reasoning as
/// `EnphaseKeychainStore`. One known trade-off specific to Viessmann: the widget extension
/// refreshes its own access token independently per device (see `HPWidgetDataSource`,
/// "refresh_token-Grant-Aufruf"), and iCloud Keychain sync isn't instantaneous — two devices
/// refreshing close together can still race, with whichever sync lands last overwriting the
/// other's newer token. Not solved here; same class of problem already accepted for the Apple
/// Watch design (see BACKLOG.md, "Zielplattform Apple Watch"), just between two iOS devices now
/// instead of iPhone+Watch.
struct ViessmannKeychainStore: ViessmannSecretStoring {
    private let service: String

    init(service: String = "de.florian.tobias.Energie.viessmann") {
        self.service = service
    }

    func read(_ key: ViessmannSecretKey) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ key: ViessmannSecretKey, value: String?) {
        let query = baseQuery(for: key)

        guard let value, let data = value.data(using: .utf8) else {
            SecItemDelete(query as CFDictionary)
            return
        }

        // See EnphaseKeychainStore.write: without an explicit kSecAttrAccessible, items default
        // to kSecAttrAccessibleWhenUnlocked and are unreadable to the widget extension's
        // background timeline refresh whenever the device is locked — which is routinely the
        // case. Needed here from the start since this heat-pump widget's entire point is
        // background access (the pressure alarm must fire even while the app is closed).
        // **Not** the "ThisDeviceOnly" variant (F0.3): incompatible with `kSecAttrSynchronizable`
        // — see EnphaseKeychainStore.write for why.
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

    /// See `EnphaseKeychainStore.baseQuery` — same reasoning for why
    /// `kSecAttrSynchronizable: true` has to be consistent across read/update/add/delete.
    private func baseQuery(for key: ViessmannSecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecAttrSynchronizable as String: true,
        ]
    }
}

/// In-memory stand-in for tests and SwiftUI previews.
final class InMemoryViessmannSecretStore: ViessmannSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ViessmannSecretKey: String] = [:]

    init(seed: [ViessmannSecretKey: String] = [:]) {
        storage = seed
    }

    func read(_ key: ViessmannSecretKey) -> String? {
        lock.withLock { storage[key] }
    }

    func write(_ key: ViessmannSecretKey, value: String?) {
        lock.withLock { storage[key] = value }
    }
}
