//
//  EnphaseOAuthClientTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

extension NetworkMockedTests {

@Suite
struct EnphaseOAuthClientTests {
    private let credentials = EnphaseCredentials(clientID: "client-1", clientSecret: "secret-1", apiKey: "key-1")

    @Test func completeSignInThrowsWithoutCodeInCallback() async {
        let client = EnphaseOAuthClient(urlSession: MockURLProtocol.makeSession())
        let callbackURL = URL(string: "de.florian.tobias.energie://enphase-oauth-callback")!
        await #expect(throws: EnphaseOAuthError.missingCode) {
            try await client.completeSignIn(callbackURL: callbackURL, credentials: credentials)
        }
    }

    @Test func completeSignInDecodesTokensAndSendsBasicAuth() async throws {
        var capturedAuthHeader: String?
        MockURLProtocol.requestHandler = { request in
            capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
            return MockURLProtocol.jsonResponse(
                url: request.url!,
                json: #"{"access_token":"at-1","refresh_token":"rt-1","expires_in":3600}"#
            )
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let client = EnphaseOAuthClient(urlSession: MockURLProtocol.makeSession(), now: { now })
        let callbackURL = URL(string: "de.florian.tobias.energie://enphase-oauth-callback?code=auth-code-1")!

        let tokens = try await client.completeSignIn(callbackURL: callbackURL, credentials: credentials)

        #expect(tokens.accessToken == "at-1")
        #expect(tokens.refreshToken == "rt-1")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
        let expectedAuth = "Basic " + Data("client-1:secret-1".utf8).base64EncodedString()
        #expect(capturedAuthHeader == expectedAuth)
    }

    @Test func completeSignInThrowsHTTPErrorOnFailureStatus() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 401, json: #"{"error":"invalid_grant"}"#)
        }
        let client = EnphaseOAuthClient(urlSession: MockURLProtocol.makeSession())
        let callbackURL = URL(string: "de.florian.tobias.energie://enphase-oauth-callback?code=bad-code")!

        await #expect(throws: (any Error).self) {
            try await client.completeSignIn(callbackURL: callbackURL, credentials: credentials)
        }
    }

    @Test func refreshDecodesNewTokens() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(
                url: request.url!,
                json: #"{"access_token":"at-2","refresh_token":"rt-2","expires_in":7200}"#
            )
        }
        let now = Date(timeIntervalSince1970: 2_000_000)
        let client = EnphaseOAuthClient(urlSession: MockURLProtocol.makeSession(), now: { now })
        let oldTokens = EnphaseTokens(accessToken: "old", refreshToken: "old-refresh", expiresAt: now)

        let refreshed = try await client.refresh(tokens: oldTokens, credentials: credentials)

        #expect(refreshed.accessToken == "at-2")
        #expect(refreshed.expiresAt == now.addingTimeInterval(7200))
    }

    @Test func authorizationURLDelegatesToEndpoints() {
        let client = EnphaseOAuthClient()
        #expect(client.authorizationURL(clientID: "abc") == EnphaseEndpoints.authorizationURL(clientID: "abc"))
    }

    @Test func allErrorCasesHaveADescription() {
        #expect(EnphaseOAuthError.missingCode.errorDescription != nil)
        #expect(EnphaseOAuthError.invalidResponse.errorDescription != nil)
        let httpError = EnphaseOAuthError.http(status: 401, body: "invalid_grant")
        #expect(httpError.errorDescription?.contains("401") == true)
        #expect(httpError.errorDescription?.contains("invalid_grant") == true)
    }
}

}
