//
//  HeatPumpModelTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import SwiftData
import Testing
@testable import Energie

extension NetworkMockedTests {

@MainActor
@Suite
struct HeatPumpModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: HeatPumpEfficiencySample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeSettings(complete: Bool = true, signedIn: Bool = true, deviceSelected: Bool = true) -> ViessmannSettings {
        let settings = ViessmannSettings(store: InMemoryViessmannSecretStore())
        if complete {
            settings.setCredentials(clientID: "client-1")
        }
        if signedIn {
            settings.setTokens(ViessmannTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: Date().addingTimeInterval(3600)))
        }
        if deviceSelected {
            settings.setDeviceSelection(ViessmannDeviceSelection(installationID: 1, gatewaySerial: "SER1", deviceID: "0"))
        }
        return settings
    }

    private nonisolated static func featuresJSON(pressure: Double = 1.7) -> String {
        #"""
        { "data": [
            { "feature": "heating.power.consumption.summary.heating", "isEnabled": true, "isReady": true, "timestamp": null, "properties": { "currentDay": { "type": "number", "value": 2.5, "unit": "kilowattHour" } } },
            { "feature": "heating.heat.production.summary.heating", "isEnabled": true, "isReady": true, "timestamp": null, "properties": { "currentDay": { "type": "number", "value": 8.0, "unit": "kilowattHour" } } },
            { "feature": "heating.sensors.pressure.supply", "isEnabled": true, "isReady": true, "timestamp": null, "properties": { "value": { "type": "number", "value": \#(pressure), "unit": "bar" } } }
        ] }
        """#
    }

    private func makePressureAlertSettings() -> HeatPumpPressureAlertSettings {
        HeatPumpPressureAlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    private func makeModel(
        settings: ViessmannSettings,
        pressureAlertSettings: HeatPumpPressureAlertSettings? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> HeatPumpModel {
        try HeatPumpModel(
            settings: settings,
            modelContext: makeContext(),
            pressureAlertSettings: pressureAlertSettings ?? makePressureAlertSettings(),
            urlSession: MockURLProtocol.makeSession(),
            now: now
        )
    }

    @Test func initialStateIsNeedsCredentialsWhenIncomplete() throws {
        let model = try makeModel(settings: makeSettings(complete: false, signedIn: false))
        #expect(model.state == .needsCredentials)
    }

    @Test func initialStateIsNeedsSignInWhenCredentialsCompleteButNoTokens() throws {
        let model = try makeModel(settings: makeSettings(complete: true, signedIn: false))
        #expect(model.state == .needsSignIn)
    }

    @Test func refreshFetchesFeaturesAndCapturesEfficiencySnapshot() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: Self.featuresJSON())
        }
        let now = Date()
        let settings = makeSettings()
        let container = try ModelContainer(for: HeatPumpEfficiencySample.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let model = HeatPumpModel(
            settings: settings, modelContext: context,
            pressureAlertSettings: HeatPumpPressureAlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!),
            urlSession: MockURLProtocol.makeSession(), now: { now }
        )

        await model.refresh()

        #expect(model.state == .ready)
        #expect(model.currentFeatures.count == 3)

        let todayStart = Calendar.current.startOfDay(for: now)
        let daySamples = try context.fetch(FetchDescriptor<HeatPumpEfficiencySample>(
            predicate: #Predicate { $0.period == "day" && $0.boundaryDate == todayStart }
        ))
        #expect(daySamples.first?.consumedKWh == 2.5)
        #expect(daySamples.first?.producedKWh == 8.0)
    }

    @Test func refreshResolvesDeviceSelectionWhenNotAlreadySet() async throws {
        MockURLProtocol.requestHandler = { request in
            if request.url!.path.contains("/equipment/installations") {
                return MockURLProtocol.jsonResponse(url: request.url!, json: #"""
                { "data": [{ "id": 1, "description": null, "gateways": [{ "serial": "SER1", "devices": [{ "id": "0", "deviceType": "heating", "modelId": null }] }] }] }
                """#)
            }
            return MockURLProtocol.jsonResponse(url: request.url!, json: Self.featuresJSON())
        }
        let settings = makeSettings(deviceSelected: false)
        let model = try makeModel(settings: settings)

        await model.refresh()

        #expect(model.state == .ready)
        #expect(settings.deviceSelection?.deviceID == "0")
    }

    @Test func refreshSetsRateLimitedStateOn429() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 429, headers: ["Retry-After": "60"], json: "{}")
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let model = try makeModel(settings: makeSettings(), now: { now })

        await model.refresh()

        #expect(model.state == .rateLimited(resumeAt: now.addingTimeInterval(60)))
    }

    @Test func refreshSignsOutOn401() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: "{}")
        }
        let model = try makeModel(settings: makeSettings())

        await model.refresh()

        #expect(model.state == .needsSignIn)
    }

    @Test func refreshSetsErrorStateOnOtherFailures() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: "server error")
        }
        let model = try makeModel(settings: makeSettings())

        await model.refresh()

        guard case .error = model.state else {
            Issue.record("Expected .error state, got \(model.state)")
            return
        }
    }

    @Test func refreshDoesNotCrashWhenPressureAlertIsDisabled() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: Self.featuresJSON(pressure: 0.5))
        }
        let alertSettings = HeatPumpPressureAlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        alertSettings.setEnabled(false)
        let model = try makeModel(settings: makeSettings(), pressureAlertSettings: alertSettings)

        await model.refresh()

        #expect(model.state == .ready)
    }

    @Test func signOutClearsTokensAndFeatures() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: Self.featuresJSON())
        }
        let model = try makeModel(settings: makeSettings())
        await model.refresh()
        #expect(!model.currentFeatures.isEmpty)

        model.signOut()

        #expect(model.state == .needsSignIn)
        #expect(model.currentFeatures.isEmpty)
    }

    @Test func saveCredentialsResetsTokensAndRequiresSignInAgain() throws {
        let model = try makeModel(settings: makeSettings())
        model.saveCredentials(clientID: "new-client-id")

        #expect(model.state == .needsSignIn)
        #expect(model.credentials.clientID == "new-client-id")
    }
}

}
