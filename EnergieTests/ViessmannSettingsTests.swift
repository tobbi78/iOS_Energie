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
}
