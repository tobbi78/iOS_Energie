//
//  ShellyClientTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

extension NetworkMockedTests {

@Suite
struct ShellyClientTests {
    private let credentials = ShellyCredentials(serverURI: "https://shelly-12-eu.shelly.cloud", authKey: "the-auth-key")

    private func makeClient(
        throttle: ShellyRequestThrottle = ShellyRequestThrottle(sleep: { _ in })
    ) -> ShellyClient {
        // `throttle` defaults to a no-op-sleep instance (but still a fresh one per test, never
        // `.shared`) so no test here actually waits a real second, and no test leaks throttle
        // state into another one via the same actor instance.
        ShellyClient(urlSession: MockURLProtocol.makeSession(), credentials: { [credentials] in credentials }, throttle: throttle)
    }

    // MARK: - discoverDevices — request shape

    @Test func discoverDevicesPostsToTheDeviceListEndpointWithTheAuthKey() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockURLProtocol.jsonResponse(url: request.url!, json: #"{"isok":true,"data":{"devices":[]}}"#)
        }

        _ = try await makeClient().discoverDevices()

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://shelly-12-eu.shelly.cloud/interface/device/list")
        let body = try #require(MockURLProtocol.bodyData(from: request))
        #expect(String(data: body, encoding: .utf8) == "auth_key=the-auth-key")
    }

    // MARK: - discoverDevices — tolerant decoding

    @Test func discoverDevicesDecodesAnArrayOfDevices() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            {"isok":true,"data":{"devices":[{"id":"a1b2c3","name":"Wohnzimmer","type":"PlugS"}]}}
            """#)
        }

        let devices = try await makeClient().discoverDevices()
        #expect(devices == [ShellyDiscoveredDevice(id: "a1b2c3", name: "Wohnzimmer", type: "PlugS")])
    }

    @Test func discoverDevicesDecodesADeviceDictionaryKeyedByID() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            {"isok":true,"data":{"devices":{"a1b2c3":{"name":"Wohnzimmer","type":"PlugS"}}}}
            """#)
        }

        let devices = try await makeClient().discoverDevices()
        #expect(devices == [ShellyDiscoveredDevice(id: "a1b2c3", name: "Wohnzimmer", type: "PlugS")])
    }

    @Test func discoverDevicesThrowsDiscoveryUnavailableOnHTTPFailure() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 404, json: "{}")
        }

        await #expect(throws: ShellyClientError.discoveryUnavailable) {
            try await makeClient().discoverDevices()
        }
    }

    @Test func discoverDevicesThrowsDiscoveryUnavailableOnUnrecognizedResponseShape() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"unexpected":true}"#)
        }

        await #expect(throws: ShellyClientError.discoveryUnavailable) {
            try await makeClient().discoverDevices()
        }
    }

    // MARK: - F15.1 shared throttle applies to every call, not just fetchDevices

    @Test func discoverDevicesGoesThroughTheSharedThrottleToo() async throws {
        nonisolated(unsafe) var acquireCount = 0
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"isok":true,"data":{"devices":[]}}"#)
        }
        let throttle = ShellyRequestThrottle(sleep: { _ in acquireCount += 1 })

        _ = try await makeClient(throttle: throttle).discoverDevices()
        _ = try await makeClient(throttle: throttle).discoverDevices()

        // Second call within the same 1s window must wait — proves discoverDevices() is gated by
        // the same throttle as fetchDevices(), not just a call unique to status polling.
        #expect(acquireCount == 1)
    }

    // MARK: - fetchDevices / verifyDevice — request shape

    @Test func fetchDevicesPostsToTheV2GetEndpointWithIDsAndAuthKey() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }

        _ = try await makeClient().fetchDevices(ids: ["a1b2c3"])

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v2/devices/api/get")
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "the-auth-key")

        let body = try #require(MockURLProtocol.bodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["ids"] as? [String] == ["a1b2c3"])
    }

    // `+` is a legal, unescaped character in a URL query per RFC 3986, but Shelly's server
    // decodes query parameters using form-urlencoded conventions where `+` means space — an
    // `auth_key` containing `+` must be percent-encoded to `%2B` or it gets silently corrupted
    // into a space server-side, failing auth with HTTP 401 (reported bug, F11.3).
    @Test func fetchDevicesPercentEncodesAPlusInTheAuthKey() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }

        let client = ShellyClient(
            urlSession: MockURLProtocol.makeSession(),
            credentials: { ShellyCredentials(serverURI: "https://shelly-12-eu.shelly.cloud", authKey: "abc+def/ghi=") },
            throttle: ShellyRequestThrottle(sleep: { _ in })
        )
        _ = try await client.fetchDevices(ids: ["a1b2c3"])

        let request = try #require(capturedRequest)
        let url = try #require(request.url)
        #expect(!url.absoluteString.contains("+"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "abc+def/ghi=")
    }

    @Test func fetchDevicesChunksMoreThanTenIDsIntoMultipleRequests() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }

        _ = try await makeClient().fetchDevices(ids: (1...15).map { "device\($0)" })

        #expect(requestCount == 2)
    }

    // MARK: - fetchDevices — F15.1 shared throttle paces chunks

    @Test func fetchDevicesDoesNotSleepForTenOrFewerIDs() async throws {
        nonisolated(unsafe) var sleepCount = 0
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let throttle = ShellyRequestThrottle(now: { Date(timeIntervalSince1970: 1_000) }, sleep: { _ in sleepCount += 1 })

        _ = try await makeClient(throttle: throttle).fetchDevices(ids: (1...10).map { "device\($0)" })

        #expect(sleepCount == 0)
    }

    // A fixed clock makes every `perform(_:)` call look like it happens "at the same instant" as
    // far as the throttle can tell, so each chunk after the first must wait out the full window.
    @Test func fetchDevicesSleepsOnceBetweenTwoChunks() async throws {
        nonisolated(unsafe) var sleptFor: [TimeInterval] = []
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let throttle = ShellyRequestThrottle(window: 1, now: { Date(timeIntervalSince1970: 1_000) }, sleep: { sleptFor.append($0) })

        let client = makeClient(throttle: throttle)
        _ = try await client.fetchDevices(ids: (1...15).map { "device\($0)" })

        #expect(sleptFor == [1])
    }

    @Test func fetchDevicesSleepsBeforeEveryChunkAfterTheFirst() async throws {
        nonisolated(unsafe) var sleepCount = 0
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }
        let throttle = ShellyRequestThrottle(now: { Date(timeIntervalSince1970: 1_000) }, sleep: { _ in sleepCount += 1 })

        _ = try await makeClient(throttle: throttle).fetchDevices(ids: (1...25).map { "device\($0)" })

        #expect(sleepCount == 2)
    }

    // MARK: - fetchDevices — tolerant decoding

    @Test func fetchDevicesDecodesABareArray() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","type":"PlugS","gen":2,"online":true}]"#)
        }

        let devices = try await makeClient().fetchDevices(ids: ["a1b2c3"])
        #expect(devices == [ShellyDeviceStatusDTO(id: "a1b2c3", type: "PlugS", code: nil, gen: "2", online: true, status: nil)])
    }

    @Test func fetchDevicesDecodesADataResultEnvelope() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"data":{"result":[{"id":"a1b2c3","online":false}]}}"#)
        }

        let devices = try await makeClient().fetchDevices(ids: ["a1b2c3"])
        #expect(devices == [ShellyDeviceStatusDTO(id: "a1b2c3", type: nil, code: nil, gen: nil, online: false, status: nil)])
    }

    // Regression for the F11.3 "Daten nicht im korrekten Format"-Bug: a real Shelly Plug M Gen3
    // sends `gen` as the string `"G2"` and `online` as `0`/`1`, not the `Int`/`Bool` SHELLY_API_
    // WERTE.md assumed — both previously made the *entire* response fail to decode (field-level
    // type mismatches, not an actually-unrecognized envelope), surfacing the Apple default
    // DecodingError message instead of a real status.
    @Test func fetchDevicesDecodesARealGen3PlugResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"90706953bbd4","type":"relay","code":"S3PL-30110EU","gen":"G2","online":1,"status":{"switch:0":{"output":true,"apower":6.4,"voltage":236,"current":0.047,"aenergy":{"total":319.87,"by_minute":[0,205.176,0],"minute_ts":1792013220}}}}]
            """#)
        }

        let device = try await makeClient().fetchDevices(ids: ["90706953bbd4"]).first
        #expect(device?.gen == "G2")
        #expect(device?.online == true)
        #expect(device?.status?.switch0?.apower == 6.4)
    }

    @Test func fetchDevicesThrowsStatusUnavailableOnUnrecognizedResponseShape() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"unexpected":true}"#)
        }

        await #expect(throws: ShellyClientError.statusUnavailable) {
            try await makeClient().fetchDevices(ids: ["a1b2c3"])
        }
    }

    // MARK: - fetchDevices — status decoding (F12.1)

    @Test func fetchDevicesDecodesTheSwitch0StatusForAGen2PlusDevice() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","gen":2,"online":true,"status":{"switch:0":{"output":true,"apower":123.4,"voltage":231.0,"current":0.53}}}]
            """#)
        }

        let device = try await makeClient().fetchDevices(ids: ["a1b2c3"]).first
        #expect(device?.status?.switch0 == ShellySwitchStatus(output: true, apower: 123.4, voltage: 231.0, current: 0.53))
    }

    @Test func fetchDevicesLeavesStatusNilWhenTheFieldIsAbsent() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }

        let device = try await makeClient().fetchDevices(ids: ["a1b2c3"]).first
        #expect(device?.status == nil)
    }

    @Test func fetchDevicesLeavesSwitch0NilForAGen1StatusShape() async throws {
        // Gen1 devices report `relays`/`meters` instead of a `switch:0` component
        // (SHELLY_API_WERTE.md, "Gen1") — the device lookup itself must still succeed, only the
        // metric card has nothing to show.
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","gen":1,"online":true,"status":{"relays":[{"ison":true}]}}]
            """#)
        }

        let device = try await makeClient().fetchDevices(ids: ["a1b2c3"]).first
        #expect(device?.status?.switch0 == nil)
    }

    // MARK: - testConnection (F17.1)

    @Test func testConnectionCountsOnlineDevicesAgainstTheTotalRequested() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","online":true},{"id":"d4e5f6","online":false}]
            """#)
        }

        let result = try await makeClient().testConnection(deviceIDs: ["a1b2c3", "d4e5f6"])
        #expect(result == ShellyConnectionTestResult(online: 1, total: 2))
    }

    @Test func testConnectionThrowsUnauthorizedOnADeadKey() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: "{}")
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().testConnection(deviceIDs: ["a1b2c3"])
        }
    }

    // MARK: - verifyDevice

    @Test func verifyDeviceReturnsTheMatchingDevice() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","online":true}]"#)
        }

        let device = try await makeClient().verifyDevice(id: "a1b2c3")
        #expect(device.id == "a1b2c3")
    }

    @Test func verifyDeviceThrowsDeviceNotFoundWhenMissingFromTheResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }

        await #expect(throws: ShellyClientError.deviceNotFound) {
            try await makeClient().verifyDevice(id: "a1b2c3")
        }
    }

    // MARK: - Missing credentials

    @Test func discoverDevicesThrowsMissingCredentialsWhenIncomplete() async throws {
        let client = ShellyClient(urlSession: MockURLProtocol.makeSession(), credentials: {
            ShellyCredentials(serverURI: "", authKey: "")
        })

        await #expect(throws: ShellyClientError.missingCredentials) {
            try await client.discoverDevices()
        }
    }

    // MARK: - setSwitch (F13.1) — request shape

    @Test func setSwitchPostsToTheV2SetSwitchEndpointWithIDChannelAndOn() async throws {
        nonisolated(unsafe) var capturedRequest: URLRequest?
        MockURLProtocol.requestHandler = { request in
            capturedRequest = request
            return MockURLProtocol.jsonResponse(url: request.url!, json: "{}")
        }

        try await makeClient().setSwitch(id: "a1b2c3", channel: 0, on: true)

        let request = try #require(capturedRequest)
        #expect(request.httpMethod == "POST")
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/v2/devices/api/set/switch")
        #expect(components.queryItems?.first(where: { $0.name == "auth_key" })?.value == "the-auth-key")

        let body = try #require(MockURLProtocol.bodyData(from: request))
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["id"] as? String == "a1b2c3")
        #expect(json["channel"] as? Int == 0)
        #expect(json["on"] as? Bool == true)
    }

    // MARK: - setSwitch — success / error handling

    @Test func setSwitchSucceedsOnHTTP200() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "{}")
        }

        try await makeClient().setSwitch(id: "a1b2c3", channel: 0, on: true)
    }

    @Test func setSwitchExtractsATopLevelErrorCode() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 400, json: #"{"code":"DEVICE_OFFLINE"}"#)
        }

        await #expect(throws: ShellyClientError.switchCommandFailed(code: "DEVICE_OFFLINE")) {
            try await makeClient().setSwitch(id: "a1b2c3", channel: 0, on: true)
        }
    }

    @Test func setSwitchExtractsANestedErrorCode() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 400, json: #"{"error":{"code":"DEVICE_FAILED_COMMAND"}}"#)
        }

        await #expect(throws: ShellyClientError.switchCommandFailed(code: "DEVICE_FAILED_COMMAND")) {
            try await makeClient().setSwitch(id: "a1b2c3", channel: 0, on: true)
        }
    }

    @Test func setSwitchFallsBackToANilCodeWhenTheBodyIsUnrecognized() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: #"{"message":"oops"}"#)
        }

        await #expect(throws: ShellyClientError.switchCommandFailed(code: nil)) {
            try await makeClient().setSwitch(id: "a1b2c3", channel: 0, on: true)
        }
    }

    @Test func switchCommandFailedMapsKnownCodesToDistinctMessages() {
        #expect(ShellyClientError.switchCommandFailed(code: "DEVICE_OFFLINE").errorDescription == "Die Steckdose ist offline.")
        #expect(ShellyClientError.switchCommandFailed(code: "DEVICE_FAILED_COMMAND").errorDescription != ShellyClientError.switchCommandFailed(code: "DEVICE_OFFLINE").errorDescription)
        #expect(ShellyClientError.switchCommandFailed(code: nil).errorDescription != nil)
    }

    // MARK: - Auth failure detection (F11.4)

    @Test func fetchDevicesThrowsUnauthorizedOnHTTP401() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: "{}")
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().fetchDevices(ids: ["a1b2c3"])
        }
    }

    @Test func fetchDevicesThrowsUnauthorizedOnHTTP403() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 403, json: "{}")
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().fetchDevices(ids: ["a1b2c3"])
        }
    }

    // Some older Shelly cloud endpoints are reported to answer an auth failure with HTTP 200
    // and `{"isok": false, "errors": {...}}` instead of a 4xx status — the exact shape isn't
    // officially documented (SHELLY_API_WERTE.md), so this is detected tolerantly.
    @Test func fetchDevicesThrowsUnauthorizedOnAnIsokFalseAuthErrorBody() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"isok":false,"errors":{"wrong_auth_key":"invalid"}}"#)
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().fetchDevices(ids: ["a1b2c3"])
        }
    }

    @Test func fetchDevicesThrowsUnauthorizedOnATopLevelAuthErrorCode() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 400, json: #"{"code":"WRONG_AUTH_KEY"}"#)
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().fetchDevices(ids: ["a1b2c3"])
        }
    }

    // A dead `auth_key` must not be papered over as "discovery itself is unavailable" — the
    // UI's fallback (manual device-ID entry) would fail identically, which hides the actual
    // problem from the user.
    @Test func discoverDevicesThrowsUnauthorizedInsteadOfDiscoveryUnavailable() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: "{}")
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().discoverDevices()
        }
    }

    @Test func setSwitchThrowsUnauthorizedInsteadOfSwitchCommandFailed() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: "{}")
        }

        await #expect(throws: ShellyClientError.unauthorized) {
            try await makeClient().setSwitch(id: "a1b2c3", channel: 0, on: true)
        }
    }

    @Test func unauthorizedHasAUserFacingMessage() {
        #expect(ShellyClientError.unauthorized.errorDescription != nil)
    }

    // MARK: - setSwitch — F15.1 shared throttle applies too

    @Test func setSwitchGoesThroughTheSharedThrottleToo() async throws {
        nonisolated(unsafe) var acquireCount = 0
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "{}")
        }
        let throttle = ShellyRequestThrottle(sleep: { _ in acquireCount += 1 })

        try await makeClient(throttle: throttle).setSwitch(id: "a1b2c3", channel: 0, on: true)
        try await makeClient(throttle: throttle).setSwitch(id: "a1b2c3", channel: 0, on: false)

        // Second call within the same 1s window must wait — proves setSwitch is gated by the
        // same throttle as discoverDevices/fetchDevices, not exempt as a write operation.
        #expect(acquireCount == 1)
    }
}

}
