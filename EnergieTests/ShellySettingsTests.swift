//
//  ShellySettingsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

@MainActor
struct ShellySettingsTests {
    @Test func initWithEmptyStoreLeavesEverythingEmpty() {
        let settings = ShellySettings(store: InMemoryShellySecretStore())
        #expect(!settings.credentials.isComplete)
        #expect(settings.credentials.serverURI.isEmpty)
        #expect(settings.credentials.authKey.isEmpty)
    }

    @Test func initReadsExistingCredentials() {
        let store = InMemoryShellySecretStore(seed: [
            .serverURI: "https://shelly-12-eu.shelly.cloud",
            .authKey: "key-1",
        ])
        let settings = ShellySettings(store: store)
        #expect(settings.credentials == ShellyCredentials(serverURI: "https://shelly-12-eu.shelly.cloud", authKey: "key-1"))
    }

    @Test func setCredentialsNormalizesAndPersistsTheServerURI() {
        let store = InMemoryShellySecretStore()
        let settings = ShellySettings(store: store)
        let saved = settings.setCredentials(serverURI: "shelly-12-eu.shelly.cloud", authKey: "key-1")
        #expect(saved)
        #expect(settings.credentials.serverURI == "https://shelly-12-eu.shelly.cloud")
        #expect(settings.credentials.authKey == "key-1")
        #expect(store.read(.serverURI) == "https://shelly-12-eu.shelly.cloud")
        #expect(store.read(.authKey) == "key-1")
    }

    @Test func setCredentialsRejectsAnInvalidServerURIAndStoresNothing() {
        let store = InMemoryShellySecretStore()
        let settings = ShellySettings(store: store)
        let saved = settings.setCredentials(serverURI: "http://shelly-12-eu.shelly.cloud", authKey: "key-1")
        #expect(!saved)
        #expect(!settings.credentials.isComplete)
        #expect(store.read(.serverURI) == nil)
        #expect(store.read(.authKey) == nil)
    }

    @Test func clearCredentialsResetsAndDeletesBothValues() {
        let store = InMemoryShellySecretStore(seed: [
            .serverURI: "https://shelly-12-eu.shelly.cloud",
            .authKey: "key-1",
        ])
        let settings = ShellySettings(store: store)
        settings.clearCredentials()
        #expect(!settings.credentials.isComplete)
        #expect(store.read(.serverURI) == nil)
        #expect(store.read(.authKey) == nil)
    }

    // MARK: - normalizedServerURI

    @Test func normalizesABareHostByAddingHTTPSScheme() {
        #expect(ShellySettings.normalizedServerURI("shelly-12-eu.shelly.cloud") == "https://shelly-12-eu.shelly.cloud")
    }

    @Test func acceptsAnAlreadyCorrectHTTPSURI() {
        #expect(ShellySettings.normalizedServerURI("https://shelly-12-eu.shelly.cloud") == "https://shelly-12-eu.shelly.cloud")
    }

    @Test func stripsATrailingSlash() {
        #expect(ShellySettings.normalizedServerURI("https://shelly-12-eu.shelly.cloud/") == "https://shelly-12-eu.shelly.cloud")
    }

    @Test func trimsSurroundingWhitespaceAndNewlines() {
        #expect(ShellySettings.normalizedServerURI("  shelly-12-eu.shelly.cloud \n") == "https://shelly-12-eu.shelly.cloud")
    }

    @Test func rejectsPlainHTTP() {
        #expect(ShellySettings.normalizedServerURI("http://shelly-12-eu.shelly.cloud") == nil)
    }

    @Test func rejectsAnEmptyString() {
        #expect(ShellySettings.normalizedServerURI("") == nil)
        #expect(ShellySettings.normalizedServerURI("   ") == nil)
    }

    @Test func rejectsAURIWithAPathAttached() {
        #expect(ShellySettings.normalizedServerURI("https://shelly-12-eu.shelly.cloud/v2/devices") == nil)
    }

    @Test func rejectsAnUnrelatedScheme() {
        #expect(ShellySettings.normalizedServerURI("ftp://shelly-12-eu.shelly.cloud") == nil)
    }
}
