//
//  ViessmannSettings.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

/// Credentials for the Viessmann API client, entered once by the user. Only a Client-ID is
/// needed — PKCE replaces the client secret (see Plans/Waermepumpe-Integration.md, Abschnitt 3).
struct ViessmannCredentials: Equatable {
    var clientID: String

    var isComplete: Bool {
        !clientID.isEmpty
    }
}

/// OAuth token pair returned by the Viessmann token endpoint.
struct ViessmannTokens: Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    func isExpired(now: Date, safetyMargin: TimeInterval = 60) -> Bool {
        now >= expiresAt.addingTimeInterval(-safetyMargin)
    }
}

/// Identifies the single heating device to poll, resolved once after sign-in. Keeping all three
/// IDs (rather than just a device ID) avoids re-deriving the path on every request and makes the
/// "gateway pseudo-device" gotcha an explicit, one-time choice instead of a runtime guess.
struct ViessmannDeviceSelection: Equatable {
    var installationID: Int
    var gatewaySerial: String
    var deviceID: String
}

/// Observable façade over the Keychain-backed secret store, mirroring `EnphaseSettings`.
@Observable
@MainActor
final class ViessmannSettings {
    private let store: ViessmannSecretStoring

    private(set) var credentials: ViessmannCredentials
    private(set) var tokens: ViessmannTokens?
    private(set) var deviceSelection: ViessmannDeviceSelection?

    init(store: ViessmannSecretStoring = ViessmannKeychainStore()) {
        self.store = store
        credentials = ViessmannCredentials(clientID: store.read(.clientID) ?? "")

        if let accessToken = store.read(.accessToken),
           let refreshToken = store.read(.refreshToken),
           let expiresAtString = store.read(.tokenExpiresAt),
           let expiresAtInterval = TimeInterval(expiresAtString) {
            tokens = ViessmannTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date(timeIntervalSince1970: expiresAtInterval)
            )
        }

        if let installationIDString = store.read(.installationID),
           let installationID = Int(installationIDString),
           let gatewaySerial = store.read(.gatewaySerial),
           let deviceID = store.read(.deviceID) {
            deviceSelection = ViessmannDeviceSelection(
                installationID: installationID,
                gatewaySerial: gatewaySerial,
                deviceID: deviceID
            )
        }

        // Re-save whatever was already there so its Keychain item picks up the current
        // accessibility attribute (see ViessmannKeychainStore.write/EnphaseSettings for why).
        if credentials.isComplete {
            store.write(.clientID, value: credentials.clientID)
        }
        if let tokens {
            store.write(.accessToken, value: tokens.accessToken)
            store.write(.refreshToken, value: tokens.refreshToken)
            store.write(.tokenExpiresAt, value: String(tokens.expiresAt.timeIntervalSince1970))
        }
        if let deviceSelection {
            store.write(.installationID, value: String(deviceSelection.installationID))
            store.write(.gatewaySerial, value: deviceSelection.gatewaySerial)
            store.write(.deviceID, value: deviceSelection.deviceID)
        }
    }

    func setCredentials(clientID: String) {
        credentials = ViessmannCredentials(clientID: clientID)
        store.write(.clientID, value: clientID)
    }

    func setTokens(_ tokens: ViessmannTokens?) {
        self.tokens = tokens
        store.write(.accessToken, value: tokens?.accessToken)
        store.write(.refreshToken, value: tokens?.refreshToken)
        store.write(.tokenExpiresAt, value: tokens.map { String($0.expiresAt.timeIntervalSince1970) })
    }

    func setDeviceSelection(_ selection: ViessmannDeviceSelection?) {
        deviceSelection = selection
        store.write(.installationID, value: selection.map { String($0.installationID) })
        store.write(.gatewaySerial, value: selection?.gatewaySerial)
        store.write(.deviceID, value: selection?.deviceID)
    }
}
