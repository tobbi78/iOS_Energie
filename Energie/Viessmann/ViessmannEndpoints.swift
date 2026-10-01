//
//  ViessmannEndpoints.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

/// URL/endpoint construction for the Viessmann IoT API.
///
/// **Not yet verified against a real login** (no Viessmann Client-ID/credentials were available
/// while writing this): these are the publicly documented Viessmann IoT API v1/v2 paths (same
/// ones used by the well-known `pyViCare`/Home Assistant Viessmann integrations), not something
/// copied from this project's macOS sibling (its `Viessmann/OAuthClient.swift` source wasn't
/// available here — only the behavioral summary in ERKENNTNISSE_MACOS.md). Verify/correct here
/// and in `VIESSMANN_API_WERTE.md` once the first real login happens, same as was done for
/// `EnphaseOAuthClient`.
enum ViessmannEndpoints {
    static let authorizationURL = URL(string: "https://iam.viessmann.com/idp/v3/authorize")!
    static let tokenURL = URL(string: "https://iam.viessmann.com/idp/v3/token")!
    static let apiBaseURL = URL(string: "https://api.viessmann.com")!

    /// Custom callback scheme for the OAuth redirect. Must be registered as the exact redirect
    /// URI for the Client-ID in the Viessmann developer portal: "\(callbackScheme)://\(callbackHost)".
    ///
    /// No Info.plist `CFBundleURLTypes` entry is needed: `WebAuthenticationSession` intercepts
    /// the redirect itself before it would reach the app as a regular deep link (same as Enphase).
    static let callbackScheme = "de.florian.tobias.energie"
    static let callbackHost = "viessmann-oauth-callback"

    static var redirectURI: String {
        "\(callbackScheme)://\(callbackHost)"
    }

    /// Scope requested at authorization. `offline_access` is required to receive a refresh
    /// token, so the ~10-minute poll loop doesn't need to re-prompt the user.
    static let scope = "IoT User offline_access"

    static func authorizationURL(clientID: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return components.url!
    }

    static func tokenExchangeBody(clientID: String, code: String, codeVerifier: String) -> [String: String] {
        [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code": code,
            "code_verifier": codeVerifier,
        ]
    }

    static func tokenRefreshBody(clientID: String, refreshToken: String) -> [String: String] {
        [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
    }

    static let installationsURL = URL(string: "https://api.viessmann.com/iot/v2/equipment/installations")!

    static func gatewaysURL(installationID: Int) -> URL {
        apiBaseURL.appendingPathComponent("iot/v2/equipment/installations/\(installationID)/gateways")
    }

    static func devicesURL(installationID: Int, gatewaySerial: String) -> URL {
        apiBaseURL.appendingPathComponent("iot/v2/equipment/installations/\(installationID)/gateways/\(gatewaySerial)/devices")
    }

    static func featuresURL(installationID: Int, gatewaySerial: String, deviceID: String) -> URL {
        apiBaseURL.appendingPathComponent(
            "iot/v2/features/installations/\(installationID)/gateways/\(gatewaySerial)/devices/\(deviceID)/features"
        )
    }
}
