//
//  ViessmannEndpointsTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

struct ViessmannEndpointsTests {
    @Test func redirectURICombinesSchemeAndHost() {
        #expect(ViessmannEndpoints.redirectURI == "de.florian.tobias.energie://viessmann-oauth-callback")
    }

    @Test func authorizationURLContainsPKCEParameters() {
        let url = ViessmannEndpoints.authorizationURL(clientID: "client-1", codeChallenge: "challenge-xyz", state: "state-xyz")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        #expect(items["client_id"] == "client-1")
        #expect(items["redirect_uri"] == ViessmannEndpoints.redirectURI)
        #expect(items["response_type"] == "code")
        #expect(items["code_challenge"] == "challenge-xyz")
        #expect(items["code_challenge_method"] == "S256")
        #expect(items["scope"] == ViessmannEndpoints.scope)
        #expect(items["state"] == "state-xyz")
    }

    @Test func tokenExchangeBodyContainsCodeVerifierAndCode() {
        let body = ViessmannEndpoints.tokenExchangeBody(clientID: "client-1", code: "the-code", codeVerifier: "verifier-abc")
        #expect(body["grant_type"] == "authorization_code")
        #expect(body["client_id"] == "client-1")
        #expect(body["redirect_uri"] == ViessmannEndpoints.redirectURI)
        #expect(body["code"] == "the-code")
        #expect(body["code_verifier"] == "verifier-abc")
    }

    @Test func tokenRefreshBodyContainsRefreshToken() {
        let body = ViessmannEndpoints.tokenRefreshBody(clientID: "client-1", refreshToken: "refresh-xyz")
        #expect(body["grant_type"] == "refresh_token")
        #expect(body["client_id"] == "client-1")
        #expect(body["refresh_token"] == "refresh-xyz")
    }

    @Test func installationsURLRequestsIncludeGateways() {
        let components = URLComponents(url: ViessmannEndpoints.installationsURL, resolvingAgainstBaseURL: false)!
        let items = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value) })
        #expect(items["includeGateways"] == "true")
        #expect(ViessmannEndpoints.installationsURL.path.hasSuffix("/equipment/installations"))
    }

    @Test func featuresURLIncludesInstallationGatewayAndDevice() {
        let url = ViessmannEndpoints.featuresURL(installationID: 123, gatewaySerial: "SERIAL1", deviceID: "0")
        #expect(url.path == "/iot/v2/features/installations/123/gateways/SERIAL1/devices/0/features")
    }

    @Test func apiBaseURLIncludesVersionPrefix() {
        #expect(ViessmannEndpoints.apiBaseURL.absoluteString == "https://api.viessmann-climatesolutions.com/iot/v2")
    }
}
