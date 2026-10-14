//
//  ShellySettings.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

/// Credentials for the Shelly Cloud Control API, entered once by the user (F11.1). Unlike
/// Enphase/Viessmann there is no OAuth consent flow — both values are copied directly from the
/// Shelly app ("User settings → Authorization cloud key"), see SHELLY_API_WERTE.md.
nonisolated struct ShellyCredentials: Equatable {
    var serverURI: String
    var authKey: String

    var isComplete: Bool {
        !serverURI.isEmpty && !authKey.isEmpty
    }
}

/// Observable façade over the Keychain-backed secret store (F11.1/F11.2), analogous to
/// `EnphaseSettings`/`ViessmannSettings`.
@Observable
@MainActor
final class ShellySettings {
    private let store: ShellySecretStoring

    private(set) var credentials: ShellyCredentials

    init(store: ShellySecretStoring = ShellyKeychainStore()) {
        self.store = store
        credentials = ShellyCredentials(
            serverURI: store.read(.serverURI) ?? "",
            authKey: store.read(.authKey) ?? ""
        )
    }

    /// Normalizes and stores the credentials. Returns `false` (and stores nothing) if
    /// `serverURI` doesn't parse into a usable host after normalization — the server is
    /// tenant-based and not guaranteed stable (SHELLY_API_WERTE.md), so the app must accept
    /// whatever the user pastes from their Shelly app rather than hardcoding one, but it still
    /// needs *some* validation since a malformed URI would only fail much later, at the first
    /// network request.
    @discardableResult
    func setCredentials(serverURI: String, authKey: String) -> Bool {
        guard let normalizedURI = Self.normalizedServerURI(serverURI) else { return false }
        credentials = ShellyCredentials(serverURI: normalizedURI, authKey: authKey)
        store.write(.serverURI, value: normalizedURI)
        store.write(.authKey, value: authKey)
        return true
    }

    func clearCredentials() {
        credentials = ShellyCredentials(serverURI: "", authKey: "")
        store.write(.serverURI, value: nil)
        store.write(.authKey, value: nil)
    }

    /// Normalizes a user-pasted server URI (e.g. `shelly-12-eu.shelly.cloud`,
    /// `https://shelly-12-eu.shelly.cloud/`, or with stray whitespace) into a canonical
    /// `https://host` form, or `nil` if it doesn't describe a bare host. Rejects `http://` (the
    /// Cloud Control API doesn't offer plaintext access) and anything with a path, query, or
    /// fragment attached — the stored value is meant to be just the host that `auth_key`-bearing
    /// requests get appended to (F17.1), not an arbitrary endpoint URL.
    static func normalizedServerURI(_ input: String) -> String? {
        var trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        let withScheme: String
        if trimmed.hasPrefix("https://") {
            withScheme = trimmed
        } else if trimmed.hasPrefix("http://") {
            return nil
        } else if trimmed.contains("://") {
            // Some other scheme (ftp://, ws://, …) — not a valid Shelly Cloud server URI.
            return nil
        } else {
            withScheme = "https://" + trimmed
        }

        guard let components = URLComponents(string: withScheme),
              components.scheme == "https",
              let host = components.host, !host.isEmpty,
              components.path.isEmpty,
              components.query == nil,
              components.fragment == nil,
              components.port == nil
        else {
            return nil
        }

        return "https://\(host)"
    }
}
