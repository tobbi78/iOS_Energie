//
//  ShellyKeychainStoreTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

struct ShellyKeychainStoreTests {
    /// A fresh, unique service name per test so real Keychain state never leaks between tests
    /// or across test runs.
    private func makeStore() -> ShellyKeychainStore {
        ShellyKeychainStore(service: "de.florian.tobias.Energie.tests.\(UUID().uuidString)")
    }

    @Test func readReturnsNilForUnsetKey() {
        let store = makeStore()
        #expect(store.read(.authKey) == nil)
    }

    @Test func writeThenReadRoundTrips() {
        let store = makeStore()
        store.write(.serverURI, value: "https://shelly-12-eu.shelly.cloud")
        #expect(store.read(.serverURI) == "https://shelly-12-eu.shelly.cloud")
    }

    @Test func writingNilDeletesTheValue() {
        let store = makeStore()
        store.write(.authKey, value: "key-1")
        #expect(store.read(.authKey) == "key-1")
        store.write(.authKey, value: nil)
        #expect(store.read(.authKey) == nil)
    }

    @Test func writingTwiceUpdatesTheValue() {
        let store = makeStore()
        store.write(.authKey, value: "first")
        store.write(.authKey, value: "second")
        #expect(store.read(.authKey) == "second")
    }

    @Test func differentKeysAreIndependent() {
        let store = makeStore()
        store.write(.serverURI, value: "https://shelly-12-eu.shelly.cloud")
        store.write(.authKey, value: "key-value")
        #expect(store.read(.serverURI) == "https://shelly-12-eu.shelly.cloud")
        #expect(store.read(.authKey) == "key-value")
    }

    @Test func inMemoryStoreRoundTripsAndSeeds() {
        let store = InMemoryShellySecretStore(seed: [.serverURI: "https://shelly-1-eu.shelly.cloud"])
        #expect(store.read(.serverURI) == "https://shelly-1-eu.shelly.cloud")
        store.write(.serverURI, value: "https://shelly-2-eu.shelly.cloud")
        #expect(store.read(.serverURI) == "https://shelly-2-eu.shelly.cloud")
        store.write(.serverURI, value: nil)
        #expect(store.read(.serverURI) == nil)
    }

    // F11.2: authKey grants direct device access with no refresh-token fallback (F11.4), so it
    // must stay device-local; the server URI is not a secret and may sync.
    @Test func onlyAuthKeyIsNonSynchronizable() {
        #expect(ShellySecretKey.serverURI.isSynchronizable)
        #expect(!ShellySecretKey.authKey.isSynchronizable)
    }
}
