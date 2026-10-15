//
//  ShellyModelTests.swift
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
struct ShellyModelTests {
    private let credentials = ShellyCredentials(serverURI: "https://shelly-12-eu.shelly.cloud", authKey: "the-auth-key")

    private func makeModel(
        hasCredentials: Bool = true,
        deviceList: ShellyDeviceList? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) -> ShellyModel {
        let settings = ShellySettings(store: InMemoryShellySecretStore(seed: hasCredentials ? [
            .serverURI: "https://shelly-12-eu.shelly.cloud",
            .authKey: "the-auth-key",
        ] : [:]))
        // No-op-sleep throttle, same reasoning as `ShellyClientTests.makeClient` — a fresh
        // instance per test so no test actually waits a real second or leaks state into another.
        let client = ShellyClient(
            urlSession: MockURLProtocol.makeSession(),
            credentials: { [credentials] in credentials },
            throttle: ShellyRequestThrottle(sleep: { _ in })
        )
        let resolvedDeviceList = deviceList ?? ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        return ShellyModel(
            settings: settings,
            deviceList: resolvedDeviceList,
            client: client,
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
        let model = makeModel(hasCredentials: false, deviceList: deviceList(withIDs: ["a1b2c3"]))

        await model.refresh()

        #expect(model.state == .needsCredentials)
        #expect(requestCount == 0)
    }

    @Test func noDevicesWithoutMakingARequest() async {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let model = makeModel()

        await model.refresh()

        #expect(model.state == .noDevices)
        #expect(requestCount == 0)
    }

    @Test func readyAssignsEachStatusToItsDeviceID() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42}}}]
            """#)
        }
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))

        await model.refresh()

        #expect(model.state == .ready)
        #expect(model.statuses["a1b2c3"]?.status?.switch0?.output == true)
        #expect(model.lastUpdated != nil)
    }

    @Test func httpFailureSurfacesAsError() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: "{}")
        }
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))

        await model.refresh()

        guard case .error = model.state else {
            Issue.record("Expected .error state, got \(model.state)")
            return
        }
    }

    @Test func fetchesAllSavedDevicesInASingleBatchedRequest() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let model = makeModel(deviceList: deviceList(withIDs: (1...5).map { "device\($0)" }))

        await model.refresh()

        #expect(requestCount == 1)
    }

    /// A failed refresh of already-`.ready` data must still surface the error — F12.1 doesn't
    /// try to keep showing stale readings behind a hidden failure, matching how
    /// `SolarModel`/`HeatPumpModel` handle a failed refresh.
    @Test func aFailedRefreshAfterBeingReadyStillSurfacesTheError() async throws {
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }
        await model.refresh()
        #expect(model.state == .ready)

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: "{}")
        }
        await model.refresh()

        guard case .error = model.state else {
            Issue.record("Expected .error state, got \(model.state)")
            return
        }
    }

    // MARK: - setSwitch (F13.1)

    @Test func setSwitchCallsTheClientThenRefreshes() async throws {
        nonisolated(unsafe) var setSwitchRequests = 0
        nonisolated(unsafe) var statusRequests = 0
        MockURLProtocol.requestHandler = { request in
            if request.url?.path == "/v2/devices/api/set/switch" {
                setSwitchRequests += 1
                return MockURLProtocol.jsonResponse(url: request.url!, json: "{}")
            } else {
                statusRequests += 1
                return MockURLProtocol.jsonResponse(url: request.url!, json: #"""
                [{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true}}}]
                """#)
            }
        }
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))

        try await model.setSwitch(deviceID: "a1b2c3", on: true)

        #expect(setSwitchRequests == 1)
        #expect(statusRequests == 1)
        #expect(model.state == .ready)
        #expect(model.statuses["a1b2c3"]?.status?.switch0?.output == true)
    }

    /// A failed switch command is a per-card concern (`ShellyPlugCard` shows its own alert) —
    /// it must not drop the whole screen into `.error` the way a failed `refresh()` does.
    @Test func setSwitchPropagatesTheErrorWithoutChangingState() async throws {
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }
        await model.refresh()
        #expect(model.state == .ready)

        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 400, json: #"{"code":"DEVICE_OFFLINE"}"#)
        }

        await #expect(throws: ShellyClientError.switchCommandFailed(code: "DEVICE_OFFLINE")) {
            try await model.setSwitch(deviceID: "a1b2c3", on: false)
        }
        #expect(model.state == .ready)
    }

    // MARK: - Poll loop (F16.1)

    @Test func pollingRefreshesRepeatedlyUntilStopped() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))
        model.pollInterval = 0.02

        model.startPolling()
        try await Task.sleep(for: .milliseconds(90))
        #expect(requestCount >= 2)
        model.stopPolling()
        // Cancellation is cooperative — a `refresh()` already in flight when `stopPolling()` is
        // called still completes before the loop observes `isCancelled` and exits. Give that one
        // potential in-flight call room to finish before taking the baseline.
        try await Task.sleep(for: .milliseconds(20))
        let countAfterStop = requestCount

        // No further requests arrive once stopped — give the (cancelled) loop a chance to fire
        // again if it incorrectly kept running.
        try await Task.sleep(for: .milliseconds(60))
        #expect(requestCount == countAfterStop)
    }

    @Test func startPollingTwiceKeepsASingleLoop() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let model = makeModel(deviceList: deviceList(withIDs: ["a1b2c3"]))
        model.pollInterval = 0.02

        model.startPolling()
        model.startPolling()
        try await Task.sleep(for: .milliseconds(90))
        model.stopPolling()

        // A single loop fires roughly every 20ms over ~90ms (~4-5 ticks); two concurrent loops
        // would roughly double that count.
        #expect(requestCount <= 6)
    }

    @Test func pollingPicksUpDevicesAddedAfterStart() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let list = deviceList(withIDs: [])
        let model = makeModel(deviceList: list)
        model.pollInterval = 0.02

        model.startPolling()
        try await Task.sleep(for: .milliseconds(30))
        #expect(model.state == .noDevices)
        #expect(requestCount == 0)

        list.add(ShellyDevice(id: "a1b2c3", name: "Steckdose", model: nil))
        try await Task.sleep(for: .milliseconds(60))
        model.stopPolling()

        #expect(model.state == .ready)
        #expect(requestCount >= 1)
    }
}

}
