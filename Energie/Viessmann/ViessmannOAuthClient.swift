//
//  ViessmannOAuthClient.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

enum ViessmannOAuthError: Error, LocalizedError, Equatable {
    case missingCode
    case stateMismatch
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .missingCode:
            return "Die Callback-URL enthielt keinen Autorisierungscode."
        case .stateMismatch:
            return "Die Anmeldung wurde abgebrochen, da die Callback-URL nicht zur gestarteten Anmeldung passte."
        case .invalidResponse:
            return "Viessmann hat eine unerwartete Antwort auf die Anmeldung geschickt."
        case .http(let status, let body):
            return "Viessmann-Anmeldung fehlgeschlagen (HTTP \(status)): \(body)"
        }
    }
}

/// Token response shape per the Viessmann IoT API. `refreshToken` is optional: verified against
/// the macOS sibling project (`Viessmann/OAuthClient.swift`), whose comment notes Viessmann does
/// not always return a new refresh token on a `refresh_token` grant — the previous one must be
/// kept in that case, or the next refresh has nothing to send.
private struct ViessmannTokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
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

    /// Generates a fresh PKCE pair, a random `state` value (CSRF protection, RFC 6749 §10.12)
    /// and the matching authorization URL. The caller must hold on to `pkce.codeVerifier` and
    /// `state` until `completeSignIn` to complete the proof.
    func makeAuthorizationRequest(clientID: String) -> (url: URL, pkce: ViessmannPKCE, state: String) {
        let pkce = ViessmannPKCE()
        let state = OAuthState.generate()
        let url = ViessmannEndpoints.authorizationURL(clientID: clientID, codeChallenge: pkce.codeChallenge, state: state)
        return (url, pkce, state)
    }

    /// Verifies the callback URL's `state` matches the one sent with the authorization request
    /// before extracting the code and exchanging it for tokens.
    func completeSignIn(callbackURL: URL, clientID: String, codeVerifier: String, state: String) async throws -> ViessmannTokens {
        let queryItems = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
        guard queryItems?.first(where: { $0.name == "state" })?.value == state else {
            throw ViessmannOAuthError.stateMismatch
        }
        guard let code = queryItems?.first(where: { $0.name == "code" })?.value else {
            throw ViessmannOAuthError.missingCode
        }

        let body = ViessmannEndpoints.tokenExchangeBody(clientID: clientID, code: code, codeVerifier: codeVerifier)
        return try await requestTokens(body: body, previousRefreshToken: nil)
    }

    func refresh(tokens: ViessmannTokens, clientID: String) async throws -> ViessmannTokens {
        let body = ViessmannEndpoints.tokenRefreshBody(clientID: clientID, refreshToken: tokens.refreshToken)
        return try await requestTokens(body: body, previousRefreshToken: tokens.refreshToken)
    }

    private func requestTokens(body: [String: String], previousRefreshToken: String?) async throws -> ViessmannTokens {
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
        guard let refreshToken = decoded.refreshToken ?? previousRefreshToken else {
            throw ViessmannOAuthError.invalidResponse
        }
        return ViessmannTokens(
            accessToken: decoded.accessToken,
            refreshToken: refreshToken,
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
