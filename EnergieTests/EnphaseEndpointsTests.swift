//
//  EnphaseEndpointsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

struct EnphaseEndpointsTests {
    @Test func redirectURICombinesSchemeAndHost() {
        #expect(EnphaseEndpoints.redirectURI == "de.florian.tobias.energie://enphase-oauth-callback")
    }

    @Test func authorizationURLContainsClientIDAndRedirectURI() {
        let url = EnphaseEndpoints.authorizationURL(clientID: "abc123", state: "state-xyz")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        #expect(items["response_type"] == "code")
        #expect(items["client_id"] == "abc123")
        #expect(items["redirect_uri"] == EnphaseEndpoints.redirectURI)
        #expect(items["state"] == "state-xyz")
    }

    @Test func tokenExchangeURLContainsCodeAndGrantType() {
        let url = EnphaseEndpoints.tokenExchangeURL(code: "the-code")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        #expect(items["grant_type"] == "authorization_code")
        #expect(items["code"] == "the-code")
        #expect(items["redirect_uri"] == EnphaseEndpoints.redirectURI)
    }

    @Test func tokenRefreshURLContainsRefreshToken() {
        let url = EnphaseEndpoints.tokenRefreshURL(refreshToken: "refresh-xyz")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        #expect(items["grant_type"] == "refresh_token")
        #expect(items["refresh_token"] == "refresh-xyz")
    }

    @Test func systemsURLIsStable() {
        #expect(EnphaseEndpoints.systems.absoluteString == "https://api.enphaseenergy.com/api/v4/systems")
    }

    @Test func summaryURLIncludesSystemID() {
        #expect(EnphaseEndpoints.summary(systemID: 42).absoluteString == "https://api.enphaseenergy.com/api/v4/systems/42/summary")
    }

    @Test func telemetryURLsIncludeSystemID() {
        #expect(EnphaseEndpoints.consumptionMeterTelemetry(systemID: 7).absoluteString.hasSuffix("/systems/7/telemetry/consumption_meter"))
        #expect(EnphaseEndpoints.energyImportTelemetry(systemID: 7).absoluteString.hasSuffix("/systems/7/energy_import_telemetry"))
        #expect(EnphaseEndpoints.energyExportTelemetry(systemID: 7).absoluteString.hasSuffix("/systems/7/energy_export_telemetry"))
        #expect(EnphaseEndpoints.batteryTelemetry(systemID: 7).absoluteString.hasSuffix("/systems/7/telemetry/battery"))
    }

    @Test func lifetimeURLsOmitStartDateQueryWhenNil() {
        let url = EnphaseEndpoints.energyLifetime(systemID: 7)
        #expect(!url.absoluteString.contains("start_date"))
    }

    @Test func lifetimeURLsIncludeFormattedStartDateWhenGiven() {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 3, day: 5))!
        let url = EnphaseEndpoints.energyLifetime(systemID: 7, startDate: date)
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let startDate = components.queryItems?.first(where: { $0.name == "start_date" })?.value
        #expect(startDate == "2026-03-05")
    }

    @Test func allFiveLifetimeURLsUseDistinctPaths() {
        let date = Date()
        let urls = [
            EnphaseEndpoints.energyLifetime(systemID: 1, startDate: date),
            EnphaseEndpoints.consumptionLifetime(systemID: 1, startDate: date),
            EnphaseEndpoints.energyImportLifetime(systemID: 1, startDate: date),
            EnphaseEndpoints.energyExportLifetime(systemID: 1, startDate: date),
            EnphaseEndpoints.batteryLifetime(systemID: 1, startDate: date),
        ]
        #expect(Set(urls.map(\.path)).count == 5)
    }
}
