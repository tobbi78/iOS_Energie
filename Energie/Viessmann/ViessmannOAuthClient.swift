//
//  ViessmannOAuthClient.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

enum ViessmannOAuthError: Error, LocalizedError {
    case missingCode
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingCode:
            return "Die Callback-URL enthielt keinen Autorisierungscode."
        case .invalidResponse:
            return "Viessmann hat eine unerwartete Antwort auf die Anmeldung geschickt."
        case .http(let status, let body):
            return "Viessmann-Anmeldung fehlgeschlagen (HTTP \(status)): \(body)"
        }
    }
}

/// Token response shape per the Viessmann IoT API (see ViessmannEndpoints.swift for the caveat
/// that this hasn't been verified against a real login yet).
private struct ViessmannTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// Handles the Viessmann OAuth2 PKCE authorization-code flow.
///
/// Unlike Enphase (`EnphaseOAuthClient`), Viessmann needs no client secret/API key — PKCE
/// (`ViessmannPKCE`) proves client identity instead — and the token endpoint takes a
/// form-encoded POST body rather than query parameters.
struct ViessmannOAuthClient {
    var urlSession: URLSession = .shared
    var now: @Sendable () -> Date = Date.init

    /// Generates a fresh PKCE pair and the matching authorization URL. The caller must hold on
    /// to `pkce.codeVerifier` until `completeSignIn` to complete the proof.
    func makeAuthorizationRequest(clientID: String) -> (url: URL, pkce: ViessmannPKCE) {
        let pkce = ViessmannPKCE()
        let url = ViessmannEndpoints.authorizationURL(clientID: clientID, codeChallenge: pkce.codeChallenge)
        return (url, pkce)
    }

    /// Extracts the authorization code from the callback URL and exchanges it for tokens.
    func completeSignIn(callbackURL: URL, clientID: String, codeVerifier: String) async throws -> ViessmannTokens {
        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw ViessmannOAuthError.missingCode
        }

        let body = ViessmannEndpoints.tokenExchangeBody(clientID: clientID, code: code, codeVerifier: codeVerifier)
        return try await requestTokens(body: body)
    }

    func refresh(tokens: ViessmannTokens, clientID: String) async throws -> ViessmannTokens {
        let body = ViessmannEndpoints.tokenRefreshBody(clientID: clientID, refreshToken: tokens.refreshToken)
        return try await requestTokens(body: body)
    }

    private func requestTokens(body: [String: String]) async throws -> ViessmannTokens {
        var request = URLRequest(url: ViessmannEndpoints.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ViessmannOAuthError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ViessmannOAuthError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(ViessmannTokenResponse.self, from: data)
        return ViessmannTokens(
            accessToken: decoded.accessToken,
            refreshToken: decoded.refreshToken,
            expiresAt: now().addingTimeInterval(decoded.expiresIn)
        )
    }
}

private extension CharacterSet {
    /// Stricter than `.urlQueryAllowed`: also escapes `+`, `&` and `=`, which must not appear
    /// literally inside an `application/x-www-form-urlencoded` value.
    static let urlQueryValueAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}
