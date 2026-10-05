//
//  EnphaseKeychainStoreTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

struct EnphaseKeychainStoreTests {
    /// A fresh, unique service name per test so real Keychain state never leaks between tests
    /// or across test runs.
    private func makeStore() -> EnphaseKeychainStore {
        EnphaseKeychainStore(service: "de.florian.tobias.Energie.tests.\(UUID().uuidString)")
    }

    @Test func readReturnsNilForUnsetKey() {
        let store = makeStore()
        #expect(store.read(.clientID) == nil)
    }

    @Test func writeThenReadRoundTrips() {
        let store = makeStore()
        store.write(.clientID, value: "my-client-id")
        #expect(store.read(.clientID) == "my-client-id")
    }

    @Test func writingNilDeletesTheValue() {
        let store = makeStore()
        store.write(.accessToken, value: "token-1")
        #expect(store.read(.accessToken) == "token-1")
        store.write(.accessToken, value: nil)
        #expect(store.read(.accessToken) == nil)
    }

    @Test func writingTwiceUpdatesTheValue() {
        let store = makeStore()
        store.write(.refreshToken, value: "first")
        store.write(.refreshToken, value: "second")
        #expect(store.read(.refreshToken) == "second")
    }

    @Test func differentKeysAreIndependent() {
        let store = makeStore()
        store.write(.clientID, value: "id-value")
        store.write(.clientSecret, value: "secret-value")
        #expect(store.read(.clientID) == "id-value")
        #expect(store.read(.clientSecret) == "secret-value")
    }

    @Test func inMemoryStoreRoundTripsAndSeeds() {
        let store = InMemoryEnphaseSecretStore(seed: [.systemID: "12345"])
        #expect(store.read(.systemID) == "12345")
        store.write(.systemID, value: "67890")
        #expect(store.read(.systemID) == "67890")
        store.write(.systemID, value: nil)
        #expect(store.read(.systemID) == nil)
    }

    // F9.3 mitigation (2026-10-05 security review): tokens must stay device-local, credentials
    // and non-secret metadata keep syncing via iCloud Keychain.
    @Test func onlyTokensAreNonSynchronizable() {
        #expect(EnphaseSecretKey.clientID.isSynchronizable)
        #expect(EnphaseSecretKey.clientSecret.isSynchronizable)
        #expect(EnphaseSecretKey.apiKey.isSynchronizable)
        #expect(EnphaseSecretKey.systemID.isSynchronizable)
        #expect(EnphaseSecretKey.operationalAt.isSynchronizable)
        #expect(!EnphaseSecretKey.accessToken.isSynchronizable)
        #expect(!EnphaseSecretKey.refreshToken.isSynchronizable)
        #expect(!EnphaseSecretKey.tokenExpiresAt.isSynchronizable)
    }
}
