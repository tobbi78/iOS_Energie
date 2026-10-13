//
//  ViessmannOAuthClientTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

extension NetworkMockedTests {

@Suite
struct ViessmannOAuthClientTests {
    @Test func makeAuthorizationRequestReturnsMatchingURLAndVerifier() {
        let client = ViessmannOAuthClient()
        let (url, pkce, state) = client.makeAuthorizationRequest(clientID: "client-1")
        #expect(url == ViessmannEndpoints.authorizationURL(clientID: "client-1", codeChallenge: pkce.codeChallenge, state: state))
        #expect(pkce.codeVerifier.count >= 43)
        #expect(state.count >= 43)
    }

    @Test func makeAuthorizationRequestGeneratesADifferentStateEachTime() {
        let client = ViessmannOAuthClient()
        let (_, _, state1) = client.makeAuthorizationRequest(clientID: "client-1")
        let (_, _, state2) = client.makeAuthorizationRequest(clientID: "client-1")
        #expect(state1 != state2)
    }

    @Test func completeSignInThrowsWithoutCodeInCallback() async {
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession())
        let callbackURL = URL(string: "de.florian.tobias.energie://viessmann-oauth-callback?state=state-1")!
        await #expect(throws: ViessmannOAuthError.missingCode) {
            try await client.completeSignIn(callbackURL: callbackURL, clientID: "client-1", codeVerifier: "verifier", state: "state-1")
        }
    }

    @Test func completeSignInThrowsOnStateMismatch() async {
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession())
        let callbackURL = URL(string: "de.florian.tobias.energie://viessmann-oauth-callback?code=auth-code&state=wrong-state")!
        await #expect(throws: ViessmannOAuthError.stateMismatch) {
            try await client.completeSignIn(callbackURL: callbackURL, clientID: "client-1", codeVerifier: "verifier", state: "expected-state")
        }
    }

    @Test func completeSignInDecodesTokensWithFormEncodedBody() async throws {
        nonisolated(unsafe) var capturedContentType: String?
        nonisolated(unsafe) var capturedBody: String?
        MockURLProtocol.requestHandler = { request in
            capturedContentType = request.value(forHTTPHeaderField: "Content-Type")
            capturedBody = MockURLProtocol.bodyData(from: request).map { String(data: $0, encoding: .utf8) ?? "" }
            return MockURLProtocol.jsonResponse(
                url: request.url!,
                json: #"{"access_token":"at-1","refresh_token":"rt-1","expires_in":3600}"#
            )
        }
        let now = Date(timeIntervalSince1970: 1_000_000)
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession(), now: { now })
        let callbackURL = URL(string: "de.florian.tobias.energie://viessmann-oauth-callback?code=auth-code&state=state-1")!

        let tokens = try await client.completeSignIn(callbackURL: callbackURL, clientID: "client-1", codeVerifier: "verifier-1", state: "state-1")

        #expect(tokens.accessToken == "at-1")
        #expect(tokens.refreshToken == "rt-1")
        #expect(tokens.expiresAt == now.addingTimeInterval(3600))
        #expect(capturedContentType == "application/x-www-form-urlencoded")
        #expect(capturedBody?.contains("code_verifier=verifier-1") == true)
        #expect(capturedBody?.contains("grant_type=authorization_code") == true)
    }

    @Test func completeSignInThrowsWhenNoRefreshTokenAnywhere() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"access_token":"at-1","expires_in":3600}"#)
        }
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession())
        let callbackURL = URL(string: "de.florian.tobias.energie://viessmann-oauth-callback?code=auth-code&state=state-1")!

        await #expect(throws: ViessmannOAuthError.invalidResponse) {
            try await client.completeSignIn(callbackURL: callbackURL, clientID: "client-1", codeVerifier: "verifier-1", state: "state-1")
        }
    }

    @Test func refreshFallsBackToPreviousRefreshTokenWhenOmitted() async throws {
        // Viessmann doesn't always return a new refresh_token on a refresh grant — the previous
        // one must be kept, not treated as a decode failure (see ViessmannOAuthClient doc comment).
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"access_token":"at-2","expires_in":3600}"#)
        }
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession())
        let oldTokens = ViessmannTokens(accessToken: "old", refreshToken: "rt-original", expiresAt: Date())

        let refreshed = try await client.refresh(tokens: oldTokens, clientID: "client-1")

        #expect(refreshed.accessToken == "at-2")
        #expect(refreshed.refreshToken == "rt-original")
    }

    @Test func refreshUsesNewRefreshTokenWhenProvided() async throws {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, json: #"{"access_token":"at-2","refresh_token":"rt-new","expires_in":3600}"#)
        }
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession())
        let oldTokens = ViessmannTokens(accessToken: "old", refreshToken: "rt-original", expiresAt: Date())

        let refreshed = try await client.refresh(tokens: oldTokens, clientID: "client-1")

        #expect(refreshed.refreshToken == "rt-new")
    }

    @Test func refreshThrowsHTTPErrorOnFailureStatus() async {
        MockURLProtocol.requestHandler = { request in
            MockURLProtocol.jsonResponse(url: request.url!, status: 400, json: #"{"error":"invalid_grant"}"#)
        }
        let client = ViessmannOAuthClient(urlSession: MockURLProtocol.makeSession())
        let oldTokens = ViessmannTokens(accessToken: "old", refreshToken: "rt-original", expiresAt: Date())

        await #expect(throws: (any Error).self) {
            try await client.refresh(tokens: oldTokens, clientID: "client-1")
        }
    }

    @Test func allErrorCasesHaveADescription() {
        #expect(ViessmannOAuthError.missingCode.errorDescription != nil)
        #expect(ViessmannOAuthError.stateMismatch.errorDescription != nil)
        #expect(ViessmannOAuthError.invalidResponse.errorDescription != nil)
        // F9.4 security review (2026-10-05): the raw response body must never reach the UI.
        let httpError = ViessmannOAuthError.http(status: 400, body: "invalid_grant")
        #expect(httpError.errorDescription?.contains("400") == true)
        #expect(httpError.errorDescription?.contains("invalid_grant") == false)
    }
}

}
