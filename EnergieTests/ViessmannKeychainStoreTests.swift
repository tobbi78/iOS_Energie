//
//  ViessmannKeychainStoreTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

struct ViessmannKeychainStoreTests {
    /// A fresh, unique service name per test so real Keychain state never leaks between tests
    /// or across test runs.
    private func makeStore() -> ViessmannKeychainStore {
        ViessmannKeychainStore(service: "de.florian.tobias.Energie.viessmann.tests.\(UUID().uuidString)")
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
        store.write(.gatewaySerial, value: "first")
        store.write(.gatewaySerial, value: "second")
        #expect(store.read(.gatewaySerial) == "second")
    }

    @Test func differentKeysAreIndependent() {
        let store = makeStore()
        store.write(.installationID, value: "123")
        store.write(.deviceID, value: "0")
        #expect(store.read(.installationID) == "123")
        #expect(store.read(.deviceID) == "0")
    }

    @Test func inMemoryStoreRoundTripsAndSeeds() {
        let store = InMemoryViessmannSecretStore(seed: [.installationID: "1"])
        #expect(store.read(.installationID) == "1")
        store.write(.installationID, value: "2")
        #expect(store.read(.installationID) == "2")
        store.write(.installationID, value: nil)
        #expect(store.read(.installationID) == nil)
    }
}
