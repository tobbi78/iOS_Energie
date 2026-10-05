//
//  EnphaseSettingsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 05.10.26.
//

import Foundation
import Testing
@testable import Energie

@MainActor
struct EnphaseSettingsTests {
    @Test func initWithEmptyStoreLeavesEverythingEmpty() {
        let settings = EnphaseSettings(store: InMemoryEnphaseSecretStore())
        #expect(!settings.credentials.isComplete)
        #expect(settings.tokens == nil)
        #expect(settings.systemID == nil)
        #expect(settings.operationalAt == nil)
    }

    @Test func initReadsAndResavesEverythingWhenFullyPresent() {
        let store = InMemoryEnphaseSecretStore(seed: [
            .clientID: "client-1",
            .clientSecret: "secret-1",
            .apiKey: "key-1",
            .accessToken: "access-1",
            .refreshToken: "refresh-1",
            .tokenExpiresAt: "1700000000",
            .systemID: "42",
            .operationalAt: "1600000000",
        ])

        let settings = EnphaseSettings(store: store)

        #expect(settings.credentials == EnphaseCredentials(clientID: "client-1", clientSecret: "secret-1", apiKey: "key-1"))
        #expect(settings.tokens?.accessToken == "access-1")
        #expect(settings.systemID == 42)
        #expect(settings.operationalAt == Date(timeIntervalSince1970: 1_600_000_000))

        // Re-save (see the init's doc comment) must leave a second init round-trip unchanged.
        let reloaded = EnphaseSettings(store: store)
        #expect(reloaded.credentials == settings.credentials)
        #expect(reloaded.tokens == settings.tokens)
        #expect(reloaded.systemID == settings.systemID)
        #expect(reloaded.operationalAt == settings.operationalAt)
    }

    @Test func initSkipsResaveBranchesThatHaveNoData() {
        // Credentials incomplete, no tokens/systemID/operationalAt at all — exercises the
        // `if`-guards' false paths (nothing to re-save) without crashing.
        let store = InMemoryEnphaseSecretStore(seed: [.clientID: "only-client-id"])
        let settings = EnphaseSettings(store: store)
        #expect(!settings.credentials.isComplete)
        #expect(settings.tokens == nil)
        #expect(settings.systemID == nil)
        #expect(settings.operationalAt == nil)
    }

    @Test func setCredentialsPersistsAndUpdates() {
        let store = InMemoryEnphaseSecretStore()
        let settings = EnphaseSettings(store: store)
        settings.setCredentials(clientID: "c", clientSecret: "s", apiKey: "k")
        #expect(settings.credentials == EnphaseCredentials(clientID: "c", clientSecret: "s", apiKey: "k"))
        #expect(store.read(.clientID) == "c")
    }

    @Test func setTokensNilClearsStoredTokens() {
        let store = InMemoryEnphaseSecretStore(seed: [
            .accessToken: "a", .refreshToken: "r", .tokenExpiresAt: "1700000000",
        ])
        let settings = EnphaseSettings(store: store)
        #expect(settings.tokens != nil)
        settings.setTokens(nil)
        #expect(settings.tokens == nil)
        #expect(store.read(.accessToken) == nil)
    }

    @Test func setSystemIDAndOperationalAtPersistAndClear() {
        let store = InMemoryEnphaseSecretStore()
        let settings = EnphaseSettings(store: store)

        settings.setSystemID(7)
        #expect(settings.systemID == 7)
        #expect(store.read(.systemID) == "7")

        settings.setOperationalAt(Date(timeIntervalSince1970: 1_234))
        #expect(settings.operationalAt == Date(timeIntervalSince1970: 1_234))

        settings.setSystemID(nil)
        settings.setOperationalAt(nil)
        #expect(settings.systemID == nil)
        #expect(settings.operationalAt == nil)
    }
}
