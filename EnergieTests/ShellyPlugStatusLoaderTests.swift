//
//  ShellyPlugStatusLoaderTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

extension NetworkMockedTests {

@Suite
@MainActor
struct ShellyPlugStatusLoaderTests {
    private let credentials = ShellyCredentials(serverURI: "https://shelly-12-eu.shelly.cloud", authKey: "the-auth-key")

    private func makeLoader(
        hasCredentials: Bool = true,
        deviceList: ShellyDeviceList? = nil
    ) -> ShellyPlugStatusLoader {
        let settings = ShellySettings(store: InMemoryShellySecretStore(seed: hasCredentials ? [
            .serverURI: "https://shelly-12-eu.shelly.cloud",
            .authKey: "the-auth-key",
        ] : [:]))
        let client = ShellyClient(urlSession: MockURLProtocol.makeSession(), credentials: { [credentials] in credentials })
        let resolvedDeviceList = deviceList ?? ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        return ShellyPlugStatusLoader(settings: settings, deviceList: resolvedDeviceList, client: client)
    }

    private func deviceList(withIDs ids: [String]) -> ShellyDeviceList {
        let list = ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        for id in ids {
            list.add(ShellyDevice(id: id, name: "Steckdose \(id)", model: nil))
        }
        return list
    }

    @Test func needsCredentialsWithoutMakingARequest() async {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let loader = makeLoader(hasCredentials: false, deviceList: deviceList(withIDs: ["a1b2c3"]))

        await loader.refresh()

        #expect(loader.state == .needsCredentials)
        #expect(requestCount == 0)
    }

    @Test func noDevicesWithoutMakingARequest() async {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let loader = makeLoader()

        await loader.refresh()

        #expect(loader.state == .noDevices)
        #expect(requestCount == 0)
    }

    @Test func readyAssignsEachStatusToItsDeviceID() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42}}}]
            """#)
        }
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]))

        await loader.refresh()

        #expect(loader.state == .ready)
        #expect(loader.statuses["a1b2c3"]?.status?.switch0?.output == true)
        #expect(loader.lastUpdated != nil)
    }

    @Test func httpFailureSurfacesAsError() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: "{}")
        }
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]))

        await loader.refresh()

        guard case .error = loader.state else {
            Issue.record("Expected .error state, got \(loader.state)")
            return
        }
    }

    @Test func fetchesAllSavedDevicesInASingleBatchedRequest() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let loader = makeLoader(deviceList: deviceList(withIDs: (1...5).map { "device\($0)" }))

        await loader.refresh()

        #expect(requestCount == 1)
    }

    /// A failed refresh of already-`.ready` data must still surface the error — F12.1 doesn't
    /// try to keep showing stale readings behind a hidden failure, matching how
    /// `SolarModel`/`HeatPumpModel` handle a failed refresh.
    @Test func aFailedRefreshAfterBeingReadyStillSurfacesTheError() async throws {
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]))
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }
        await loader.refresh()
        #expect(loader.state == .ready)

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: "{}")
        }
        await loader.refresh()

        guard case .error = loader.state else {
            Issue.record("Expected .error state, got \(loader.state)")
            return
        }
    }
}

}
