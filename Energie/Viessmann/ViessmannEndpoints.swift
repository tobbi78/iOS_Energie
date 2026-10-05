//
//  ViessmannEndpoints.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

/// URL/endpoint construction for the Viessmann IoT API.
///
/// Verified against the real, working implementation in the macOS sibling project
/// (https://github.com/tobbi78/Dashboard_Waermepumpe, `Viessmann/ViessmannEndpoints.swift` and
/// `Viessmann/OAuthClient.swift`) — the initial version of this file guessed at the classic
/// `viessmann.com` hostnames from public docs, which was wrong: Viessmann has since moved to
/// `viessmann-climatesolutions.com`.
enum ViessmannEndpoints {
    static let authorizationURL = URL(string: "https://iam.viessmann-climatesolutions.com/idp/v3/authorize")!
    static let tokenURL = URL(string: "https://iam.viessmann-climatesolutions.com/idp/v3/token")!
    /// Already includes the `/iot/v2` API version prefix, unlike Enphase's `baseURL`.
    static let apiBaseURL = URL(string: "https://api.viessmann-climatesolutions.com/iot/v2")!

    /// Custom callback scheme for the OAuth redirect. Must be registered as the exact redirect
    /// URI for this app's Client-ID in the Viessmann developer portal:
    /// "\(callbackScheme)://\(callbackHost)". The macOS app registered its own Client-ID with
    /// "de.florian.tobias.Dashboard-Waermepumpe://oauth-callback" — this iOS app is a different
    /// client and needs its own redirect URI added in the portal (either as a second redirect
    /// URI on the same Client-ID, if Viessmann allows more than one, or under a separate
    /// Client-ID for iOS).
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

    static func authorizationURL(clientID: String, codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    static func tokenExchangeBody(clientID: String, code: String, codeVerifier: String) -> [String: String] {
        [
            "grant_type": "authorization_code",
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "code_verifier": codeVerifier,
            "code": code,
        ]
    }

    static func tokenRefreshBody(clientID: String, refreshToken: String) -> [String: String] {
        [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshToken,
        ]
    }

    /// `includeGateways=true` returns the full installation → gateway → device tree in one call,
    /// so no separate `/gateways`/`/devices` endpoints are needed (unlike an earlier, unverified
    /// version of this file assumed).
    static var installationsURL: URL {
        var components = URLComponents(url: apiBaseURL.appendingPathComponent("equipment/installations"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "includeGateways", value: "true")]
        return components.url!
    }

    static func featuresURL(installationID: Int, gatewaySerial: String, deviceID: String) -> URL {
        apiBaseURL.appendingPathComponent(
            "features/installations/\(installationID)/gateways/\(gatewaySerial)/devices/\(deviceID)/features"
        )
    }
}
