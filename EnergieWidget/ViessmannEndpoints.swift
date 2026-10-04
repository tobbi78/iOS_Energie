//
//  ViessmannEndpoints.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Byte-identical duplicate of Energie/Viessmann/ViessmannEndpoints.swift — the widget target
//  can't link app-only source files (same tooling limitation as EnphaseRequestBudget.swift).
//  Keep both copies in sync by hand.
//

import Foundation

enum ViessmannEndpoints {
    static let authorizationURL = URL(string: "https://iam.viessmann-climatesolutions.com/idp/v3/authorize")!
    static let tokenURL = URL(string: "https://iam.viessmann-climatesolutions.com/idp/v3/token")!
    /// Already includes the `/iot/v2` API version prefix, unlike Enphase's `baseURL`.
    static let apiBaseURL = URL(string: "https://api.viessmann-climatesolutions.com/iot/v2")!

    static let callbackScheme = "de.florian.tobias.energie"
    static let callbackHost = "viessmann-oauth-callback"

    static var redirectURI: String {
        "\(callbackScheme)://\(callbackHost)"
    }

    static let scope = "IoT User offline_access"

    static func authorizationURL(clientID: String, codeChallenge: String) -> URL {
        var components = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "scope", value: scope),
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
