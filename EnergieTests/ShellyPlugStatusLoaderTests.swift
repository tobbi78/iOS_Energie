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
        deviceList: ShellyDeviceList? = nil,
        energyTracker: ShellyDailyEnergyTrackerStore? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> ShellyPlugStatusLoader {
        let settings = ShellySettings(store: InMemoryShellySecretStore(seed: hasCredentials ? [
            .serverURI: "https://shelly-12-eu.shelly.cloud",
            .authKey: "the-auth-key",
        ] : [:]))
        let client = ShellyClient(urlSession: MockURLProtocol.makeSession(), credentials: { [credentials] in credentials })
        let resolvedDeviceList = deviceList ?? ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let resolvedEnergyTracker = energyTracker ?? ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        return ShellyPlugStatusLoader(
            settings: settings,
            deviceList: resolvedDeviceList,
            client: client,
            energyTracker: resolvedEnergyTracker,
            now: now
        )
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

    // MARK: - Daily energy tracking (F12.3)

    @Test func refreshRecordsAEnergyTotalForAnOnlineDeviceWithAKnownReading() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let tracker = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42,"aenergy":{"total":123.4}}}}]
            """#)
        }
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]), energyTracker: tracker, now: { fixedNow })

        await loader.refresh()

        #expect(loader.state == .ready)
        // First-ever reading baselines at 0 Wh (nothing to diff against yet) — the point of this
        // test is that a reading was recorded at all, not the resulting value.
        #expect(tracker.energyToday(deviceID: "a1b2c3", now: fixedNow) == 0)
        #expect(loader.energyToday["a1b2c3"] == 0)
    }

    @Test func refreshDoesNotRecordAReadingForAnOfflineDevice() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let tracker = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":false,"status":{"switch:0":{"output":false,"apower":0,"aenergy":{"total":123.4}}}}]
            """#)
        }
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]), energyTracker: tracker, now: { fixedNow })

        await loader.refresh()

        #expect(loader.state == .ready)
        #expect(tracker.energyToday(deviceID: "a1b2c3", now: fixedNow) == nil)
        #expect(loader.energyToday["a1b2c3"] == nil)
    }

    @Test func refreshDoesNotRecordAReadingWithoutAKnownAenergyTotal() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let tracker = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42}}}]
            """#)
        }
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]), energyTracker: tracker, now: { fixedNow })

        await loader.refresh()

        #expect(loader.state == .ready)
        #expect(tracker.energyToday(deviceID: "a1b2c3", now: fixedNow) == nil)
        #expect(loader.energyToday["a1b2c3"] == nil)
    }

    @Test func secondRefreshAccumulatesOnTopOfTheFirstReading() async throws {
        nonisolated(unsafe) var current = Date(timeIntervalSince1970: 1_000_000)
        let tracker = ShellyDailyEnergyTrackerStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let loader = makeLoader(deviceList: deviceList(withIDs: ["a1b2c3"]), energyTracker: tracker, now: { current })

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42,"aenergy":{"total":100}}}}]
            """#)
        }
        await loader.refresh()
        #expect(loader.energyToday["a1b2c3"] == 0)

        current = current.addingTimeInterval(3600)
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42,"aenergy":{"total":150}}}}]
            """#)
        }
        await loader.refresh()

        #expect(loader.energyToday["a1b2c3"] == 50)
    }
}

}
