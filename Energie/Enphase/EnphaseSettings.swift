//
//  EnphaseSettings.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Credentials for the Enphase developer app, entered once by the user.
struct EnphaseCredentials: Equatable {
    var clientID: String
    var clientSecret: String
    var apiKey: String

    var isComplete: Bool {
        !clientID.isEmpty && !clientSecret.isEmpty && !apiKey.isEmpty
    }
}

/// OAuth token pair returned by the Enphase token endpoint.
struct EnphaseTokens: Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date

    func isExpired(now: Date, safetyMargin: TimeInterval = 60) -> Bool {
        now >= expiresAt.addingTimeInterval(-safetyMargin)
    }
}

/// Observable façade over the Keychain-backed secret store (F1.2/F1.3).
///
/// Deliberately local-only for now: iCloud-Keychain-Synchronisation across devices was part of
/// the CloudKit plan and is deferred together with it (see BACKLOG.md Epic 0).
@Observable
@MainActor
final class EnphaseSettings {
    private let store: EnphaseSecretStoring

    private(set) var credentials: EnphaseCredentials
    private(set) var tokens: EnphaseTokens?
    private(set) var systemID: Int?
    /// Commissioning/grid-connection date of the system, used as the backfill start point
    /// (F3.2) instead of an arbitrary fixed window.
    private(set) var operationalAt: Date?

    init(store: EnphaseSecretStoring = EnphaseKeychainStore()) {
        self.store = store
        credentials = EnphaseCredentials(
            clientID: store.read(.clientID) ?? "",
            clientSecret: store.read(.clientSecret) ?? "",
            apiKey: store.read(.apiKey) ?? ""
        )

        if let accessToken = store.read(.accessToken),
           let refreshToken = store.read(.refreshToken),
           let expiresAtString = store.read(.tokenExpiresAt),
           let expiresAtInterval = TimeInterval(expiresAtString) {
            tokens = EnphaseTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: Date(timeIntervalSince1970: expiresAtInterval)
            )
        }

        if let systemIDString = store.read(.systemID), let id = Int(systemIDString) {
            systemID = id
        }

        if let operationalAtString = store.read(.operationalAt), let interval = TimeInterval(operationalAtString) {
            operationalAt = Date(timeIntervalSince1970: interval)
        }
    }

    func setCredentials(clientID: String, clientSecret: String, apiKey: String) {
        credentials = EnphaseCredentials(clientID: clientID, clientSecret: clientSecret, apiKey: apiKey)
        store.write(.clientID, value: clientID)
        store.write(.clientSecret, value: clientSecret)
        store.write(.apiKey, value: apiKey)
    }

    func setTokens(_ tokens: EnphaseTokens?) {
        self.tokens = tokens
        store.write(.accessToken, value: tokens?.accessToken)
        store.write(.refreshToken, value: tokens?.refreshToken)
        store.write(.tokenExpiresAt, value: tokens.map { String($0.expiresAt.timeIntervalSince1970) })
    }

    func setSystemID(_ systemID: Int?) {
        self.systemID = systemID
        store.write(.systemID, value: systemID.map(String.init))
    }

    func setOperationalAt(_ date: Date?) {
        operationalAt = date
        store.write(.operationalAt, value: date.map { String($0.timeIntervalSince1970) })
    }
}
