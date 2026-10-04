//
//  EnphaseOAuthClient.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

enum EnphaseOAuthError: Error, LocalizedError, Equatable {
    case missingCode
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingCode:
            return "Die Callback-URL enthielt keinen Autorisierungscode."
        case .invalidResponse:
            return "Enphase hat eine unerwartete Antwort auf die Anmeldung geschickt."
        case .http(let status, let body):
            return "Enphase-Anmeldung fehlgeschlagen (HTTP \(status)): \(body)"
        }
    }
}

/// Token response shape as documented in ENPHASE_API_WERTE.md — not yet verified against a
/// real token exchange. Adjust here (and update the doc) once the first real login happens.
private struct EnphaseTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// Handles the Enphase OAuth2 authorization-code flow.
///
/// Unlike Viessmann's PKCE flow (see ERKENNTNISSE_MACOS.md), Enphase requires a client secret
/// (HTTP Basic at the token endpoint) and sends all token-exchange parameters as query items
/// rather than a form body.
struct EnphaseOAuthClient {
    var urlSession: URLSession = .shared
    var now: @Sendable () -> Date = Date.init

    func authorizationURL(clientID: String) -> URL {
        EnphaseEndpoints.authorizationURL(clientID: clientID)
    }

    /// Extracts the authorization code from the callback URL and exchanges it for tokens.
    func completeSignIn(callbackURL: URL, credentials: EnphaseCredentials) async throws -> EnphaseTokens {
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw EnphaseOAuthError.missingCode
        }

        let url = EnphaseEndpoints.tokenExchangeURL(code: code)
        return try await requestTokens(url: url, credentials: credentials)
    }

    func refresh(tokens: EnphaseTokens, credentials: EnphaseCredentials) async throws -> EnphaseTokens {
        let url = EnphaseEndpoints.tokenRefreshURL(refreshToken: tokens.refreshToken)
        return try await requestTokens(url: url, credentials: credentials)
    }

    private func requestTokens(url: URL, credentials: EnphaseCredentials) async throws -> EnphaseTokens {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let basicAuth = Data("\(credentials.clientID):\(credentials.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basicAuth)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnphaseOAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw EnphaseOAuthError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(EnphaseTokenResponse.self, from: data)
        return EnphaseTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: now().addingTimeInterval(decoded.expiresIn)
        )
    }
}
