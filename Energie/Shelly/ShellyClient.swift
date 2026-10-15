//
//  ShellyClient.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import os

private let shellyClientLogger = Logger(subsystem: "de.florian.tobias.Energie", category: "ShellyClient")

enum ShellyClientError: Error, LocalizedError, Equatable {
    case missingCredentials
    case invalidResponse
    case http(status: Int, body: String)
    /// The `auth_key` was rejected — most likely because the Shelly account's password changed
    /// (SHELLY_API_WERTE.md: this invalidates `auth_key` with no refresh-token mechanism to fall
    /// back on, unlike Enphase/Viessmann). Detected from HTTP 401/403, or — since the exact error
    /// envelope isn't officially documented — tolerantly from a 2xx body that still signals
    /// failure (see `ShellyClient.isAuthFailure`). Takes priority over `.http`/`.discoveryUnavailable`/
    /// `.switchCommandFailed` so the app can tell "dead key" apart from any other failure.
    case unauthorized
    /// `/interface/device/list` responded with something this app's tolerant decoding (see
    /// `ShellyDTO.swift`) couldn't make sense of, or the request itself failed — it's only
    /// community-documented, not official (SHELLY_API_WERTE.md). The UI falls back to manual
    /// device-ID entry in this case rather than presenting a dead end.
    case discoveryUnavailable
    /// `v2/devices/api/get` returned no entry for a requested device ID — most likely a typo in
    /// a manually entered ID, or a device that doesn't belong to this account.
    case deviceNotFound
    /// `v2/devices/api/get` responded with something this app's tolerant decoding (see
    /// `ShellyDeviceStatusResponse`) couldn't make sense of. The raw body goes to the logger
    /// only, never to the user — same reasoning as `.http`'s `body`.
    case statusUnavailable
    /// `v2/devices/api/set/switch` (F13.1) failed. `code` is Shelly's documented error code
    /// (SHELLY_API_WERTE.md: `DEVICE_OFFLINE`, `DEVICE_FAILED_COMMAND`, `DEVICE_INVALID_MODE`,
    /// `DEVICE_INVALID_CHANNEL`, `BAD_REQUEST`, `DEVICE_NOT_FOUND`, `INSTANCE_NOT_FOUND`,
    /// `UNEXPECTED_SUBSERVICE_ERROR`) when `ShellyClient.setSwitch` could extract one from the
    /// response body, `nil` otherwise — the exact error body shape isn't officially documented,
    /// so extraction is best-effort (see `setSwitch`).
    case switchCommandFailed(code: String?)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Shelly-Zugangsdaten fehlen. Bitte zuerst Server-URI und Schlüssel hinterlegen."
        case .invalidResponse:
            return "Shelly hat eine unerwartete Antwort geschickt."
        case .http(let status, _):
            // `body` kept on the error case for diagnostics only, same reasoning as
            // EnphaseClientError.http/ViessmannClientError.http — never shown to the user.
            return "Shelly-Anfrage fehlgeschlagen (HTTP \(status))."
        case .unauthorized:
            return "Der Shelly-Schlüssel wurde abgelehnt. Wurde das Passwort des Shelly-Kontos geändert? Bitte den neuen Schlüssel in den Einstellungen hinterlegen."
        case .discoveryUnavailable:
            return "Automatische Geräteerkennung nicht verfügbar. Bitte Geräte-ID manuell eingeben."
        case .deviceNotFound:
            return "Kein Gerät mit dieser ID gefunden. Bitte die Geräte-ID in der Shelly-App prüfen."
        case .statusUnavailable:
            return "Gerätestatus konnte nicht gelesen werden. Bitte später erneut versuchen."
        case .switchCommandFailed(let code):
            switch code {
            case "DEVICE_OFFLINE":
                return "Die Steckdose ist offline."
            case "DEVICE_FAILED_COMMAND":
                return "Der Schaltbefehl ist fehlgeschlagen. Bitte erneut versuchen."
            case "DEVICE_NOT_FOUND", "INSTANCE_NOT_FOUND":
                return "Steckdose nicht gefunden."
            default:
                return "Schalten fehlgeschlagen. Bitte später erneut versuchen."
            }
        }
    }
}

/// Access to the Shelly Cloud Control API using just the `auth_key` already in
/// `ShellyCredentials` — no OAuth token, unlike `EnphaseClient`/`ViessmannClient`. Every call
/// goes through the shared, account-wide 1-request/second throttle (F15.1) before hitting the
/// network, whether it's a direct user action (F11.3's "automatisch suchen") or a background
/// refresh from `ShellyModel`'s poll loop (F16.1).
struct ShellyClient {
    var urlSession: URLSession = .shared
    /// Async (not just `@Sendable`) so the closure can safely hop onto `ShellySettings`'s
    /// `@MainActor` isolation at call time (`{ await settings.credentials }`), the same pattern
    /// `EnphaseClient.accessToken`/`ViessmannClient`-style closures use for their own
    /// `@MainActor`-isolated settings objects — a plain synchronous `@Sendable` closure could
    /// not read MainActor-isolated state from an arbitrary calling context.
    var credentials: @Sendable () async -> ShellyCredentials
    /// Defaults to the shared, app-wide instance (see `ShellyRequestThrottle.shared`) since
    /// `ShellyClient` itself still has no single long-lived owner — `ShellyModel` holds one for
    /// polling, but `ShellyDevicesScreen` constructs its own for device verification (F11.3).
    var throttle: ShellyRequestThrottle = .shared

    /// F11.3 "Geräte automatisch suchen". Any failure — network, HTTP, or an unrecognized
    /// response shape — surfaces as `.discoveryUnavailable` rather than the underlying error,
    /// since the UI's fallback is always the same regardless of *why* discovery failed (manual
    /// entry).
    func discoverDevices() async throws -> [ShellyDiscoveredDevice] {
        let credentials = try await requireCredentials()
        do {
            let request = ShellyEndpoints.deviceListRequest(server: credentials.serverURI, authKey: credentials.authKey)
            let data = try await perform(request)
            return try JSONDecoder().decode(ShellyDeviceListResponse.self, from: data).devices
        } catch ShellyClientError.unauthorized {
            // A dead `auth_key` isn't "discovery itself is unavailable" — the UI's manual-entry
            // fallback would just fail identically, so this surfaces distinctly (F11.4).
            throw ShellyClientError.unauthorized
        } catch {
            throw ShellyClientError.discoveryUnavailable
        }
    }

    /// F11.3 manual-entry verification, and (unmodified) reused for F12 status polling later.
    /// Chunks into batches of 10 — the API's per-call maximum (SHELLY_API_WERTE.md) — even
    /// though F11.3 itself only ever calls this with a single ID. For more than one chunk
    /// (F12.2: more than 10 saved devices), each chunk is its own request through `perform(_:)`,
    /// so the shared throttle (F15.1) already paces them without any extra logic here.
    func fetchDevices(ids: [String]) async throws -> [ShellyDeviceStatusDTO] {
        guard !ids.isEmpty else { return [] }
        let credentials = try await requireCredentials()

        var devices: [ShellyDeviceStatusDTO] = []
        for chunk in ids.chunked(into: 10) {
            let request = ShellyEndpoints.deviceStatusRequest(server: credentials.serverURI, authKey: credentials.authKey, ids: chunk)
            let data = try await perform(request)
            do {
                devices.append(contentsOf: try JSONDecoder().decode(ShellyDeviceStatusResponse.self, from: data).devices)
            } catch {
                // Diagnostic for an unrecognized status response shape — the raw body is the
                // only way to find out what a real device actually sent (SHELLY_API_WERTE.md,
                // "Noch offen"), but must never reach the user (see `.statusUnavailable`).
                let body = String(data: data, encoding: .utf8) ?? ""
                shellyClientLogger.error("Shelly device-status response for \(chunk.joined(separator: ","), privacy: .public) had an unrecognized shape: \(body, privacy: .public)")
                throw ShellyClientError.statusUnavailable
            }
        }
        return devices
    }

    /// Looks up exactly one device ID and throws `.deviceNotFound` if it's missing from the
    /// response — used by the manual-entry flow (F11.3), where a missing device almost
    /// certainly means a typo rather than something to silently ignore.
    func verifyDevice(id: String) async throws -> ShellyDeviceStatusDTO {
        guard let device = try await fetchDevices(ids: [id]).first(where: { $0.id == id }) else {
            throw ShellyClientError.deviceNotFound
        }
        return device
    }

    /// F13.1 "Ein/Aus-Schalten" — the app's first write access to a real device. On failure,
    /// tries to extract Shelly's documented error code from the response body (`code` at the top
    /// level, or nested under `error.code` — the exact error envelope isn't officially
    /// documented, see SHELLY_API_WERTE.md, so this is best-effort) and rethrows as
    /// `.switchCommandFailed`, which maps known codes to a user-facing message.
    func setSwitch(id: String, channel: Int, on: Bool) async throws {
        let credentials = try await requireCredentials()
        let request = ShellyEndpoints.setSwitchRequest(server: credentials.serverURI, authKey: credentials.authKey, id: id, channel: channel, on: on)
        do {
            _ = try await perform(request)
        } catch ShellyClientError.http(_, let body) {
            throw ShellyClientError.switchCommandFailed(code: Self.errorCode(fromResponseBody: body))
        }
    }

    private static func errorCode(fromResponseBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let code = json["code"] as? String {
            return code
        }
        if let error = json["error"] as? [String: Any], let code = error["code"] as? String {
            return code
        }
        return nil
    }

    /// Known top-level/`error.code` values that mean "the `auth_key` itself was rejected" rather
    /// than some other failure — not officially documented (SHELLY_API_WERTE.md), best-effort
    /// like `errorCode(fromResponseBody:)` above.
    private static let authErrorCodes: Set<String> = ["UNAUTHORIZED", "WRONG_AUTH_KEY", "INVALID_AUTH_KEY", "UNAUTHENTICATED"]

    /// Whether this response signals a rejected `auth_key` (F11.4). Checked on *every* response,
    /// not just non-2xx ones: the older `/interface/device/list`-style endpoints are reported to
    /// sometimes answer auth failures with HTTP 200 and `{"isok": false, "errors": {...}}`
    /// instead of a 4xx status.
    private static func isAuthFailure(statusCode: Int, body: String) -> Bool {
        if statusCode == 401 || statusCode == 403 {
            return true
        }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let code = json["code"] as? String, authErrorCodes.contains(code.uppercased()) {
            return true
        }
        if let error = json["error"] as? [String: Any], let code = error["code"] as? String, authErrorCodes.contains(code.uppercased()) {
            return true
        }
        if let isok = json["isok"] as? Bool, !isok, let errors = json["errors"] as? [String: Any] {
            return errors.keys.contains { key in
                let lowercased = key.lowercased()
                return lowercased.contains("auth") || lowercased.contains("token")
            }
        }
        return false
    }

    private func requireCredentials() async throws -> ShellyCredentials {
        let credentials = await credentials()
        guard credentials.isComplete else { throw ShellyClientError.missingCredentials }
        return credentials
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        await throttle.acquire()
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShellyClientError.invalidResponse
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        if Self.isAuthFailure(statusCode: httpResponse.statusCode, body: body) {
            throw ShellyClientError.unauthorized
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ShellyClientError.http(status: httpResponse.statusCode, body: body)
        }
        return data
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
