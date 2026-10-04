//
//  ViessmannClientTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

extension NetworkMockedTests {

@Suite
struct ViessmannClientTests {
    private func makeClient(accessToken: String = "token-1") -> ViessmannClient {
        ViessmannClient(urlSession: MockURLProtocol.makeSession(), accessToken: { accessToken })
    }

    @Test func fetchInstallationsSendsBearerTokenAndDecodesResponse() async throws {
        var capturedAuthHeader: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            return MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            { "data": [{ "id": 1, "description": "Zuhause", "gateways": [] }] }
            """#)
        }
        let installations = try await makeClient(accessToken: "token-abc").fetchInstallations()
        #expect(installations.first?.id == 1)
        #expect(capturedAuthHeader == "Bearer token-abc")
    }

    @Test func fetchFeaturesDecodesResponse() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            { "data": [{ "feature": "heating.sensors.temperature.outside", "isEnabled": true, "isReady": true, "timestamp": null, "properties": {} }] }
            """#)
        }
        let features = try await makeClient().fetchFeatures(installationID: 1, gatewaySerial: "SER1", deviceID: "0")
        #expect(features.first?.feature == "heating.sensors.temperature.outside")
    }

    @Test func performThrowsUnauthorizedOn401() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: "{}")
        }
        await #expect(throws: ViessmannClientError.unauthorized) {
            try await makeClient().fetchInstallations()
        }
    }

    @Test func performThrowsRateLimitedWithRetryAfterOn429() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 429, headers: ["Retry-After": "120"], json: "{}")
        }
        do {
            _ = try await makeClient().fetchInstallations()
            Issue.record("Expected rateLimited to be thrown")
        } catch ViessmannClientError.rateLimited(let retryAfter) {
            #expect(retryAfter == 120)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func performThrowsHTTPErrorOnOtherFailureStatus() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 500, json: "server error")
        }
        await #expect(throws: (any Error).self) {
            try await makeClient().fetchInstallations()
        }
    }

    @Test func resolveDefaultDeviceSelectionThrowsWhenNoInstallation() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{ "data": [] }"#)
        }
        await #expect(throws: ViessmannClientError.noInstallationFound) {
            try await makeClient().resolveDefaultDeviceSelection()
        }
    }

    @Test func resolveDefaultDeviceSelectionThrowsWhenNoGateway() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            { "data": [{ "id": 1, "description": null, "gateways": [] }] }
            """#)
        }
        await #expect(throws: ViessmannClientError.noGatewayFound) {
            try await makeClient().resolveDefaultDeviceSelection()
        }
    }

    @Test func resolveDefaultDeviceSelectionThrowsWhenNoDevice() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            { "data": [{ "id": 1, "description": null, "gateways": [{ "serial": "SER1", "devices": [] }] }] }
            """#)
        }
        await #expect(throws: ViessmannClientError.noDeviceFound) {
            try await makeClient().resolveDefaultDeviceSelection()
        }
    }

    @Test func resolveDefaultDeviceSelectionPicksNonGatewayDevice() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"""
            { "data": [{ "id": 42, "description": null, "gateways": [{ "serial": "SER1", "devices": [
                { "id": "gateway", "deviceType": "gateway", "modelId": null },
                { "id": "0", "deviceType": "heating", "modelId": "Vitocal250A" }
            ] }] }] }
            """#)
        }
        let selection = try await makeClient().resolveDefaultDeviceSelection()
        #expect(selection.installationID == 42)
        #expect(selection.gatewaySerial == "SER1")
        #expect(selection.deviceID == "0")
    }
}

}
