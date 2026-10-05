//
//  ViessmannSettingsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 05.10.26.
//

import Foundation
import Testing
@testable import Energie

@MainActor
struct ViessmannSettingsTests {
    @Test func initWithEmptyStoreLeavesEverythingEmpty() {
        let settings = ViessmannSettings(store: InMemoryViessmannSecretStore())
        #expect(!settings.credentials.isComplete)
        #expect(settings.tokens == nil)
        #expect(settings.deviceSelection == nil)
    }

    @Test func initReadsAndResavesEverythingWhenFullyPresent() {
        let store = InMemoryViessmannSecretStore(seed: [
            .clientID: "client-1",
            .accessToken: "access-1",
            .refreshToken: "refresh-1",
            .tokenExpiresAt: "1700000000",
            .installationID: "99",
            .gatewaySerial: "gw-1",
            .deviceID: "device-1",
        ])

        let settings = ViessmannSettings(store: store)

        #expect(settings.credentials == ViessmannCredentials(clientID: "client-1"))
        #expect(settings.tokens?.accessToken == "access-1")
        #expect(settings.deviceSelection == ViessmannDeviceSelection(installationID: 99, gatewaySerial: "gw-1", deviceID: "device-1"))

        // Re-save (see the init's doc comment) must leave a second init round-trip unchanged.
        let reloaded = ViessmannSettings(store: store)
        #expect(reloaded.credentials == settings.credentials)
        #expect(reloaded.tokens == settings.tokens)
        #expect(reloaded.deviceSelection == settings.deviceSelection)
    }

    @Test func initSkipsResaveBranchesThatHaveNoData() {
        let store = InMemoryViessmannSecretStore()
        let settings = ViessmannSettings(store: store)
        #expect(!settings.credentials.isComplete)
        #expect(settings.tokens == nil)
        #expect(settings.deviceSelection == nil)
    }

    @Test func setCredentialsPersistsAndUpdates() {
        let store = InMemoryViessmannSecretStore()
        let settings = ViessmannSettings(store: store)
        settings.setCredentials(clientID: "c")
        #expect(settings.credentials == ViessmannCredentials(clientID: "c"))
        #expect(store.read(.clientID) == "c")
    }

    @Test func setTokensNilClearsStoredTokens() {
        let store = InMemoryViessmannSecretStore(seed: [
            .accessToken: "a", .refreshToken: "r", .tokenExpiresAt: "1700000000",
        ])
        let settings = ViessmannSettings(store: store)
        #expect(settings.tokens != nil)
        settings.setTokens(nil)
        #expect(settings.tokens == nil)
        #expect(store.read(.accessToken) == nil)
    }

    @Test func setDeviceSelectionNilClearsStoredSelection() {
        let store = InMemoryViessmannSecretStore()
        let settings = ViessmannSettings(store: store)

        settings.setDeviceSelection(ViessmannDeviceSelection(installationID: 1, gatewaySerial: "gw", deviceID: "dev"))
        #expect(settings.deviceSelection != nil)
        #expect(store.read(.installationID) == "1")

        settings.setDeviceSelection(nil)
        #expect(settings.deviceSelection == nil)
        #expect(store.read(.installationID) == nil)
    }

    // F9.6 security review (2026-10-05): the widget extension refreshes tokens independently in
    // its own process and writes to the same Keychain item — these guard against either side
    // overwriting the other's newer result.

    @Test func reloadTokensFromStorePicksUpAnExternallyWrittenChange() {
        let store = InMemoryViessmannSecretStore(seed: [
            .accessToken: "a1", .refreshToken: "r1", .tokenExpiresAt: "1700000000",
        ])
        let settings = ViessmannSettings(store: store)
        #expect(settings.tokens?.accessToken == "a1")

        // Simulate the widget extension writing fresher tokens directly to the shared Keychain.
        store.write(.accessToken, value: "a2")
        store.write(.refreshToken, value: "r2")
        store.write(.tokenExpiresAt, value: "1800000000")

        let reloaded = settings.reloadTokensFromStore()
        #expect(reloaded?.accessToken == "a2")
        #expect(settings.tokens?.accessToken == "a2")
    }

    @Test func adoptRefreshedTokensPersistsWhenRefreshTokenUnchanged() {
        let store = InMemoryViessmannSecretStore(seed: [
            .accessToken: "a1", .refreshToken: "r1", .tokenExpiresAt: "1700000000",
        ])
        let settings = ViessmannSettings(store: store)
        let refreshed = ViessmannTokens(accessToken: "a2", refreshToken: "r2", expiresAt: Date(timeIntervalSince1970: 1_800_000_000))

        let result = settings.adoptRefreshedTokens(refreshed, previousRefreshToken: "r1")

        #expect(result.accessToken == "a2")
        #expect(settings.tokens?.accessToken == "a2")
        #expect(store.read(.accessToken) == "a2")
    }

    @Test func adoptRefreshedTokensDiscardsOwnResultWhenRefreshTokenAlreadyRotated() {
        let store = InMemoryViessmannSecretStore(seed: [
            .accessToken: "a1", .refreshToken: "r1", .tokenExpiresAt: "1700000000",
        ])
        let settings = ViessmannSettings(store: store)

        // Simulate the widget extension having already refreshed (and rotated the refresh
        // token) concurrently, between this call's token read and its write-back attempt.
        store.write(.accessToken, value: "widget-a2")
        store.write(.refreshToken, value: "widget-r2")
        store.write(.tokenExpiresAt, value: "1800000000")

        let ownRefreshResult = ViessmannTokens(accessToken: "own-a2", refreshToken: "own-r2", expiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        let result = settings.adoptRefreshedTokens(ownRefreshResult, previousRefreshToken: "r1")

        // Adopts the widget's result instead of overwriting it with its own.
        #expect(result.accessToken == "widget-a2")
        #expect(settings.tokens?.accessToken == "widget-a2")
        #expect(store.read(.accessToken) == "widget-a2")
    }
}
