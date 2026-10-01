//
//  ViessmannClient.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

enum ViessmannClientError: Error, LocalizedError {
    case invalidResponse
    case http(status: Int, body: String)
    case noInstallationFound
    case noGatewayFound
    case noDeviceFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Viessmann hat eine unerwartete Antwort geschickt."
        case .http(let status, let body):
            return "Viessmann-Anfrage fehlgeschlagen (HTTP \(status)): \(body)"
        case .noInstallationFound:
            return "Es wurde keine Viessmann-Installation für dieses Konto gefunden."
        case .noGatewayFound:
            return "Es wurde kein Gateway für diese Installation gefunden."
        case .noDeviceFound:
            return "Es wurde kein Gerät für dieses Gateway gefunden."
        }
    }
}

/// Authenticated Viessmann API access for equipment discovery (installation → gateway → device).
/// Unlike Enphase there is no known fixed rate limit (see ERKENNTNISSE_MACOS.md) — only a safe
/// polling cadence (5–15 min) — so, unlike `EnphaseClient`, no throttle/budget gate is needed
/// here; the poll cadence itself is enforced by `HeatPumpModel`'s timer (HP-2).
struct ViessmannClient {
    var urlSession: URLSession = .shared
    var accessToken: @Sendable () async throws -> String

    func fetchInstallations() async throws -> [ViessmannInstallationDTO] {
        let response: ViessmannListResponse<ViessmannInstallationDTO> = try await perform(ViessmannEndpoints.installationsURL)
        return response.data
    }

    func fetchGateways(installationID: Int) async throws -> [ViessmannGatewayDTO] {
        let response: ViessmannListResponse<ViessmannGatewayDTO> = try await perform(
            ViessmannEndpoints.gatewaysURL(installationID: installationID)
        )
        return response.data
    }

    func fetchDevices(installationID: Int, gatewaySerial: String) async throws -> [ViessmannDeviceDTO] {
        let response: ViessmannListResponse<ViessmannDeviceDTO> = try await perform(
            ViessmannEndpoints.devicesURL(installationID: installationID, gatewaySerial: gatewaySerial)
        )
        return response.data
    }

    /// Walks installation → gateway → device and picks the best-effort heating device (not the
    /// gateway pseudo-device). Used once after sign-in to resolve `ViessmannDeviceSelection`.
    func resolveDefaultDeviceSelection() async throws -> ViessmannDeviceSelection {
        guard let installation = try await fetchInstallations().first else {
            throw ViessmannClientError.noInstallationFound
        }
        guard let gateway = try await fetchGateways(installationID: installation.id).first else {
            throw ViessmannClientError.noGatewayFound
        }
        let devices = try await fetchDevices(installationID: installation.id, gatewaySerial: gateway.serial)
        guard let device = devices.mostLikelyHeatingDevice else {
            throw ViessmannClientError.noDeviceFound
        }
        return ViessmannDeviceSelection(installationID: installation.id, gatewaySerial: gateway.serial, deviceID: device.id)
    }

    private func perform<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ViessmannClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ViessmannClientError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
