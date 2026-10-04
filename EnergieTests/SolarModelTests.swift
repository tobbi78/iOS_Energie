//
//  SolarModelTests.swift
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
struct SolarModelTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: PVDailySample.self, PVYearlySample.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeSettings(complete: Bool = true, signedIn: Bool = true) -> EnphaseSettings {
        let settings = EnphaseSettings(store: InMemoryEnphaseSecretStore())
        if complete {
            settings.setCredentials(clientID: "client-1", clientSecret: "secret-1", apiKey: "key-1")
        }
        if signedIn {
            settings.setTokens(EnphaseTokens(accessToken: "at-1", refreshToken: "rt-1", expiresAt: Date().addingTimeInterval(3600)))
        }
        return settings
    }

    private static func successHandler() -> @Sendable (URLRequest) throws -> (HTTPURLResponse, Data) {
        { request in
            let path = request.url!.path
            let json: String
            switch true {
            case path.hasSuffix("/summary"):
                json = #"{"energy_today":12345,"current_power":500}"#
            case path.hasSuffix("/telemetry/consumption_meter"):
                json = #"{"intervals":[{"end_at":1,"enwh":10000}]}"#
            case path.hasSuffix("/energy_import_telemetry"):
                json = #"{"intervals":[[{"end_at":1,"wh_imported":4000}]]}"#
            case path.hasSuffix("/energy_export_telemetry"):
                json = #"{"intervals":[[{"end_at":1,"wh_exported":1000}]]}"#
            case path.hasSuffix("/telemetry/battery"):
                json = #"{"intervals":[{"end_at":1,"charge":{"enwh":500},"discharge":{"enwh":200},"soc":{"percent":55}}]}"#
            case path.hasSuffix("/systems"):
                json = #"{"systems":[{"system_id":42,"operational_at":1000000}]}"#
            default:
                throw URLError(.badURL)
            }
            return MockURLProtocol.jsonResponse(url: request.url!, json: json)
        }
    }

    private func makeModel(settings: EnphaseSettings, now: @escaping @Sendable () -> Date = { Date() }) throws -> SolarModel {
        try SolarModel(
            settings: settings,
            modelContext: makeContext(),
            throttle: EnphaseRequestThrottle(),
            budget: EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!),
            urlSession: MockURLProtocol.makeSession(),
            userDefaults: UserDefaults(suiteName: UUID().uuidString)!,
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

    @Test func refreshFetchesAndStoresTodaysSample() async throws {
        MockURLProtocol.requestHandler = Self.successHandler()
        let model = try makeModel(settings: makeSettings())

        await model.refresh()

        #expect(model.state == .ready)
        #expect(model.today?.producedWh == 12345)
        #expect(model.today?.consumedWh == 10000)
        #expect(model.today?.importedWh == 4000)
        #expect(model.today?.exportedWh == 1000)
        #expect(model.today?.batterySocPercent == 55)
        #expect(model.systemID == 42)
    }

    @Test func refreshSetsErrorStateOnHTTPFailure() async throws {
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

    @Test func signOutClearsTokensAndTodayButKeepsCredentials() async throws {
        MockURLProtocol.requestHandler = Self.successHandler()
        let settings = makeSettings()
        let model = try makeModel(settings: settings)
        await model.refresh()
        #expect(model.today != nil)

        model.signOut()

        #expect(model.state == .needsSignIn)
        #expect(model.today == nil)
        #expect(model.credentials.isComplete)
    }

    @Test func saveCredentialsResetsTokensAndRequiresSignInAgain() throws {
        let model = try makeModel(settings: makeSettings())
        model.saveCredentials(clientID: "new-id", clientSecret: "new-secret", apiKey: "new-key")

        #expect(model.state == .needsSignIn)
        #expect(model.credentials.clientID == "new-id")
    }

    @Test func requestsUsedThisMonthDelegatesToBudget() async throws {
        MockURLProtocol.requestHandler = Self.successHandler()
        let model = try makeModel(settings: makeSettings())
        #expect(await model.requestsUsedThisMonth() == 0)

        await model.refresh()

        #expect(await model.requestsUsedThisMonth() > 0)
    }
}

}
