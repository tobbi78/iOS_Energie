//
//  ViessmannPKCETests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 01.10.26.
//

import Testing
@testable import Energie

struct ViessmannPKCETests {

    /// Official RFC 7636 Appendix B test vector — the one piece of the Viessmann auth flow that
    /// can be verified without a real account (see ViessmannEndpoints.swift for what's unverified).
    @Test func codeChallengeMatchesRFC7636TestVector() {
        let pkce = ViessmannPKCE(codeVerifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.codeChallenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedVerifierHasValidLength() {
        let verifier = ViessmannPKCE.makeCodeVerifier()
        #expect(verifier.count >= 43 && verifier.count <= 128)
    }

    @Test func mostLikelyHeatingDevicePrefersNonGatewayDevice() {
        let devices = [
            ViessmannDeviceDTO(id: "gateway", deviceType: "gateway", modelId: nil, status: nil),
            ViessmannDeviceDTO(id: "0", deviceType: "heating", modelId: "Vitocal250A", status: "Online"),
        ]
        #expect(devices.mostLikelyHeatingDevice?.id == "0")
    }

    @Test func mostLikelyHeatingDeviceFallsBackToFirstWhenAmbiguous() {
        let devices = [ViessmannDeviceDTO(id: "0", deviceType: nil, modelId: nil, status: nil)]
        #expect(devices.mostLikelyHeatingDevice?.id == "0")
    }
}
