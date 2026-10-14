//
//  ShellyClient.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

enum ShellyClientError: Error, LocalizedError, Equatable {
    case missingCredentials
    case invalidResponse
    case http(status: Int, body: String)
    /// `/interface/device/list` responded with something this app's tolerant decoding (see
    /// `ShellyDTO.swift`) couldn't make sense of, or the request itself failed — it's only
    /// community-documented, not official (SHELLY_API_WERTE.md). The UI falls back to manual
    /// device-ID entry in this case rather than presenting a dead end.
    case discoveryUnavailable
    /// `v2/devices/api/get` returned no entry for a requested device ID — most likely a typo in
    /// a manually entered ID, or a device that doesn't belong to this account.
    case deviceNotFound

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
        case .discoveryUnavailable:
            return "Automatische Geräteerkennung nicht verfügbar. Bitte Geräte-ID manuell eingeben."
        case .deviceNotFound:
            return "Kein Gerät mit dieser ID gefunden. Bitte die Geräte-ID in der Shelly-App prüfen."
        }
    }
}

/// Access to the Shelly Cloud Control API using just the `auth_key` already in
/// `ShellyCredentials` — no OAuth token, and (unlike `EnphaseClient`) no budget/throttle gate
/// yet, since F11.3 only ever calls this on direct user action (tapping "automatisch suchen" or
/// "prüfen und hinzufügen"), never from a background poll loop. F15.1 adds the shared
/// 1-request/second throttle once polling needs it.
struct ShellyClient {
    var urlSession: URLSession = .shared
    /// Async (not just `@Sendable`) so the closure can safely hop onto `ShellySettings`'s
    /// `@MainActor` isolation at call time (`{ await settings.credentials }`), the same pattern
    /// `EnphaseClient.accessToken`/`ViessmannClient`-style closures use for their own
    /// `@MainActor`-isolated settings objects — a plain synchronous `@Sendable` closure could
    /// not read MainActor-isolated state from an arbitrary calling context.
    var credentials: @Sendable () async -> ShellyCredentials
    /// F12.2: pause between chunks in `fetchDevices` when more than 10 IDs are requested, so a
    /// large device list can't blow through the account-wide 1-request/second limit on its own
    /// — a stopgap until F15.1's shared throttle covers every Shelly call, not just this one.
    var chunkDelay: Duration = .seconds(1)
    /// Swappable so tests don't have to actually wait — same reasoning as the `now`/`sleep`
    /// seams elsewhere in this codebase (e.g. `EnphaseRequestThrottle`).
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

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
        } catch {
            throw ShellyClientError.discoveryUnavailable
        }
    }

    /// F11.3 manual-entry verification, and (unmodified) reused for F12 status polling later.
    /// Chunks into batches of 10 — the API's per-call maximum (SHELLY_API_WERTE.md) — even
    /// though F11.3 itself only ever calls this with a single ID. For more than one chunk
    /// (F12.2: more than 10 saved devices), waits `chunkDelay` before every chunk after the
    /// first, so this one call alone can't exceed the account-wide 1-request/second limit.
    func fetchDevices(ids: [String]) async throws -> [ShellyDeviceStatusDTO] {
        guard !ids.isEmpty else { return [] }
        let credentials = try await requireCredentials()

        var devices: [ShellyDeviceStatusDTO] = []
        for (index, chunk) in ids.chunked(into: 10).enumerated() {
            if index > 0 {
                try await sleep(chunkDelay)
            }
            let request = ShellyEndpoints.deviceStatusRequest(server: credentials.serverURI, authKey: credentials.authKey, ids: chunk)
            let data = try await perform(request)
            devices.append(contentsOf: try JSONDecoder().decode(ShellyDeviceStatusResponse.self, from: data).devices)
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

    private func requireCredentials() async throws -> ShellyCredentials {
        let credentials = await credentials()
        guard credentials.isComplete else { throw ShellyClientError.missingCredentials }
        return credentials
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ShellyClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ShellyClientError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
