//
//  ViessmannPKCETests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation
import Testing
@testable import Energie

struct ViessmannPKCETests {

    /// Official RFC 7636 Appendix B test vector — verified identical to the macOS sibling
    /// project's own `PKCE.challenge(forVerifier:)`.
    @Test func codeChallengeMatchesRFC7636TestVector() {
        let pkce = ViessmannPKCE(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifierHasValidLength() {
        let verifier = ViessmannPKCE.makeCodeVerifier()
        #expect(verifier.count >= 43 && verifier.count <= 128)
    }

    /// The gateway pseudo-device's `id` is literally `"gateway"` — confirmed via the real bug/fix
    /// in the macOS sibling project (`DashboardModel.gatewayPseudoDeviceID`).
    @Test func mostLikelyHeatingDevicePrefersNonGatewayDevice() {
        let devices = [
            ViessmannDeviceDTO(id: "gateway", deviceType: nil, modelId: nil),
            ViessmannDeviceDTO(id: "0", deviceType: "heating", modelId: "Vitocal250A"),
        ]
        #expect(devices.mostLikelyHeatingDevice?.id == "0")
    }

    @Test func mostLikelyHeatingDeviceFallsBackToFirstWhenAmbiguous() {
        let devices = [ViessmannDeviceDTO(id: "0", deviceType: nil, modelId: nil)]
        #expect(devices.mostLikelyHeatingDevice?.id == "0")
    }

    @Test func decodesNestedInstallationsResponse() throws {
        let json = """
        { "data": [{
            "id": 123456,
            "description": "Zuhause",
            "gateways": [{
                "serial": "7633061234567890",
                "devices": [
                    { "id": "gateway", "deviceType": "gateway", "modelId": null },
                    { "id": "0", "deviceType": "heating", "modelId": "Vitocal250A" }
                ]
            }]
        }] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.viessmann.decode(ViessmannListResponse<ViessmannInstallationDTO>.self, from: json)
        let installation = try #require(decoded.data.first)
        let gateway = try #require(installation.gateways.first)
        #expect(installation.id == 123456)
        #expect(gateway.serial == "7633061234567890")
        #expect(gateway.devices.mostLikelyHeatingDevice?.id == "0")
    }

    @Test func decodesHeterogeneousFeatureValues() throws {
        let json = """
        { "data": [{
            "feature": "heating.sensors.temperature.outside",
            "isEnabled": true,
            "isReady": true,
            "timestamp": "2026-09-22T10:00:00.123Z",
            "properties": {
                "status": { "type": "string", "value": "connected", "unit": null },
                "value": { "type": "number", "value": 16.8, "unit": "celsius" }
            }
        }] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder.viessmann.decode(ViessmannListResponse<ViessmannFeatureDTO>.self, from: json)
        let feature = try #require(decoded.data.first)
        #expect(feature.feature == "heating.sensors.temperature.outside")
        #expect(feature.properties["value"]?.value.numericValue == 16.8)
        #expect(feature.properties["status"]?.value.stringRepresentation == "connected")
        #expect(feature.timestamp != nil)
    }
}
