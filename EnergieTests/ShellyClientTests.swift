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
        chunkDelay: Duration = .seconds(1),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> ShellyClient {
        // `sleep` defaults to a no-op here so every test *not* specifically about the F12.2
        // chunk delay doesn't actually wait a real second per extra chunk.
        ShellyClient(urlSession: MockURLProtocol.makeSession(), credentials: { [credentials] in credentials }, chunkDelay: chunkDelay, sleep: sleep)
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

    @Test func fetchDevicesChunksMoreThanTenIDsIntoMultipleRequests() async throws {
        nonisolated(unsafe) var requestCount = 0
        MockURLProtocol.requestHandler = { request in
            requestCount += 1
            return MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }

        _ = try await makeClient().fetchDevices(ids: (1...15).map { "device\($0)" })

        #expect(requestCount == 2)
    }

    // MARK: - fetchDevices — F12.2 pause between chunks

    @Test func fetchDevicesDoesNotSleepForTenOrFewerIDs() async throws {
        nonisolated(unsafe) var sleepCount = 0
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }

        _ = try await makeClient(sleep: { _ in sleepCount += 1 }).fetchDevices(ids: (1...10).map { "device\($0)" })

        #expect(sleepCount == 0)
    }

    @Test func fetchDevicesSleepsOnceBetweenTwoChunks() async throws {
        nonisolated(unsafe) var sleptDurations: [Duration] = []
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }

        let client = makeClient(chunkDelay: .seconds(1), sleep: { sleptDurations.append($0) })
        _ = try await client.fetchDevices(ids: (1...15).map { "device\($0)" })

        #expect(sleptDurations == [.seconds(1)])
    }

    @Test func fetchDevicesSleepsBeforeEveryChunkAfterTheFirst() async throws {
        nonisolated(unsafe) var sleepCount = 0
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: "[]")
        }

        _ = try await makeClient(sleep: { _ in sleepCount += 1 }).fetchDevices(ids: (1...25).map { "device\($0)" })

        #expect(sleepCount == 2)
    }

    // MARK: - fetchDevices — tolerant decoding

    @Test func fetchDevicesDecodesABareArray() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"[{"id":"a1b2c3","type":"PlugS","gen":2,"online":true}]"#)
        }

        let devices = try await makeClient().fetchDevices(ids: ["a1b2c3"])
        #expect(devices == [ShellyDeviceStatusDTO(id: "a1b2c3", type: "PlugS", code: nil, gen: 2, online: true, status: nil)])
    }

    @Test func fetchDevicesDecodesADataResultEnvelope() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"data":{"result":[{"id":"a1b2c3","online":false}]}}"#)
        }

        let devices = try await makeClient().fetchDevices(ids: ["a1b2c3"])
        #expect(devices == [ShellyDeviceStatusDTO(id: "a1b2c3", type: nil, code: nil, gen: nil, online: false, status: nil)])
    }

    // MARK: - fetchDevices — status decoding (F12.1)

    @Test func fetchDevicesDecodesTheSwitch0StatusForAGen2PlusDevice() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            [{"id":"a1b2c3","gen":2,"online":true,"status":{"switch:0":{"output":true,"apower":123.4,"voltage":231.0,"current":0.53}}}]
            """#)
        }

        let device = try await makeClient().fetchDevices(ids: ["a1b2c3"]).first
        #expect(device?.status?.switch0 == ShellySwitchStatus(output: true, apower: 123.4, voltage: 231.0, current: 0.53, aenergy: nil))
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
}

}
