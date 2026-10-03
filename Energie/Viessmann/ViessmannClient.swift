//
//  ViessmannClient.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import Foundation

enum ViessmannClientError: Error, LocalizedError {
    case invalidResponse
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(status: Int, body: String)
    case noInstallationFound
    case noGatewayFound
    case noDeviceFound

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Viessmann hat eine unerwartete Antwort geschickt."
        case .unauthorized:
            return "Die Viessmann-Anmeldung ist abgelaufen oder ungültig."
        case .rateLimited(let retryAfter):
            if let retryAfter {
                return "Viessmann-Anfragelimit erreicht. Nächster Versuch in \(Int(retryAfter))s."
            }
            return "Viessmann-Anfragelimit erreicht. Bitte später erneut versuchen."
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

/// Authenticated Viessmann API access for equipment discovery and feature polling. Unlike
/// Enphase there is no known fixed rate limit (see ERKENNTNISSE_MACOS.md) — only a safe polling
/// cadence (5–15 min) — so, unlike `EnphaseClient`, no throttle/budget gate is needed here; the
/// poll cadence itself is enforced by `HeatPumpModel`'s timer (HP-2). 429 responses are still
/// handled defensively, same as the macOS sibling project does.
struct ViessmannClient {
    var urlSession: URLSession = .shared
    var accessToken: @Sendable () async throws -> String

    /// `includeGateways=true` returns the full installation → gateway → device tree in one call.
    func fetchInstallations() async throws -> [ViessmannInstallationDTO] {
        let response: ViessmannListResponse<ViessmannInstallationDTO> = try await perform(ViessmannEndpoints.installationsURL)
        return response.data
    }

    func fetchFeatures(installationID: Int, gatewaySerial: String, deviceID: String) async throws -> [ViessmannFeatureDTO] {
        let response: ViessmannListResponse<ViessmannFeatureDTO> = try await perform(
            ViessmannEndpoints.featuresURL(installationID: installationID, gatewaySerial: gatewaySerial, deviceID: deviceID)
        )
        return response.data
    }

    /// Walks installation → gateway → device and picks the best-effort heating device (not the
    /// gateway pseudo-device). Used once after sign-in to resolve `ViessmannDeviceSelection`.
    func resolveDefaultDeviceSelection() async throws -> ViessmannDeviceSelection {
        guard let installation = try await fetchInstallations().first else {
            throw ViessmannClientError.noInstallationFound
        }
        guard let gateway = installation.gateways.first else {
            throw ViessmannClientError.noGatewayFound
        }
        guard let device = gateway.devices.mostLikelyHeatingDevice else {
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
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw ViessmannClientError.unauthorized
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw ViessmannClientError.rateLimited(retryAfter: retryAfter)
        default:
            throw ViessmannClientError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder.viessmann.decode(T.self, from: data)
    }
}
