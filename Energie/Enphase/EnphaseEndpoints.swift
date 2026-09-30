//
//  EnphaseEndpoints.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// URL/endpoint construction for the Enphase Monitoring API v4.
///
/// Reference: ENPHASE_API_WERTE.md (repo root).
enum EnphaseEndpoints {
    static let baseURL = URL(string: "https://api.enphaseenergy.com")!

    /// Custom callback scheme for the OAuth redirect. Must be registered as the app's
    /// redirect URI in the Enphase developer portal: "\(callbackScheme)://\(callbackHost)".
    ///
    /// No Info.plist `CFBundleURLTypes` entry is needed for this: `WebAuthenticationSession`
    /// intercepts the redirect itself before it would reach the app as a regular deep link.
    static let callbackScheme = "de.florian.tobias.energie"
    static let callbackHost = "enphase-oauth-callback"

    static var redirectURI: String {
        "\(callbackScheme)://\(callbackHost)"
    }

    static func authorizationURL(clientID: String) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        return components.url!
    }

    static func tokenExchangeURL(code: String) -> URL {
        tokenURL(queryItems: [
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code", value: code),
        ])
    }

    static func tokenRefreshURL(refreshToken: String) -> URL {
        tokenURL(queryItems: [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
        ])
    }

    private static func tokenURL(queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("oauth/token"), resolvingAgainstBaseURL: false)!
        components.queryItems = queryItems
        return components.url!
    }

    static var systems: URL {
        baseURL.appendingPathComponent("api/v4/systems")
    }

    static func summary(systemID: Int) -> URL {
        baseURL.appendingPathComponent("api/v4/systems/\(systemID)/summary")
    }

    static func consumptionMeterTelemetry(systemID: Int) -> URL {
        baseURL.appendingPathComponent("api/v4/systems/\(systemID)/telemetry/consumption_meter")
    }

    static func energyImportTelemetry(systemID: Int) -> URL {
        baseURL.appendingPathComponent("api/v4/systems/\(systemID)/energy_import_telemetry")
    }

    static func energyExportTelemetry(systemID: Int) -> URL {
        baseURL.appendingPathComponent("api/v4/systems/\(systemID)/energy_export_telemetry")
    }

    static func batteryTelemetry(systemID: Int) -> URL {
        baseURL.appendingPathComponent("api/v4/systems/\(systemID)/telemetry/battery")
    }

    // MARK: - Lifetime (daily) series, used for backfill (F3.2) and daily finalize (F3.3)

    static func energyLifetime(systemID: Int, startDate: Date? = nil) -> URL {
        lifetimeURL(path: "api/v4/systems/\(systemID)/energy_lifetime", startDate: startDate)
    }

    static func consumptionLifetime(systemID: Int, startDate: Date? = nil) -> URL {
        lifetimeURL(path: "api/v4/systems/\(systemID)/consumption_lifetime", startDate: startDate)
    }

    static func energyImportLifetime(systemID: Int, startDate: Date? = nil) -> URL {
        lifetimeURL(path: "api/v4/systems/\(systemID)/energy_import_lifetime", startDate: startDate)
    }

    static func energyExportLifetime(systemID: Int, startDate: Date? = nil) -> URL {
        lifetimeURL(path: "api/v4/systems/\(systemID)/energy_export_lifetime", startDate: startDate)
    }

    static func batteryLifetime(systemID: Int, startDate: Date? = nil) -> URL {
        lifetimeURL(path: "api/v4/systems/\(systemID)/battery_lifetime", startDate: startDate)
    }

    private static let lifetimeDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    private static func lifetimeURL(path: String, startDate: Date?) -> URL {
        guard let startDate else { return baseURL.appendingPathComponent(path) }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "start_date", value: lifetimeDateFormatter.string(from: startDate))]
        return components.url!
    }
}
