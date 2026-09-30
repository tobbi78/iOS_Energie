//
//  EnphaseClient.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

enum EnphaseClientError: Error, LocalizedError {
    case invalidResponse
    case http(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Enphase hat eine unerwartete Antwort geschickt."
        case .http(let status, let body):
            return "Enphase-Anfrage fehlgeschlagen (HTTP \(status)): \(body)"
        }
    }
}

/// Authenticated Enphase API access. Every request carries both required headers
/// (`Authorization: Bearer <token>` and `key: <API key>`, see ENPHASE_API_WERTE.md) and passes
/// through the shared minute throttle first.
struct EnphaseClient {
    var urlSession: URLSession = .shared
    var throttle: EnphaseRequestThrottle
    var apiKey: @Sendable () -> String
    var accessToken: @Sendable () async throws -> String

    func fetchSystems() async throws -> [EnphaseSystemDTO] {
        let response: EnphaseSystemsResponse = try await perform(EnphaseEndpoints.systems)
        return response.systems
    }

    func fetchSummary(systemID: Int) async throws -> EnphaseSystemSummaryDTO {
        try await perform(EnphaseEndpoints.summary(systemID: systemID))
    }

    func fetchConsumptionToday(systemID: Int) async throws -> EnphaseMeterTelemetryResponse {
        try await perform(EnphaseEndpoints.consumptionMeterTelemetry(systemID: systemID))
    }

    func fetchImportedEnergyToday(systemID: Int) async throws -> EnphaseEnergyFlowTelemetryResponse {
        try await perform(EnphaseEndpoints.energyImportTelemetry(systemID: systemID))
    }

    func fetchExportedEnergyToday(systemID: Int) async throws -> EnphaseEnergyFlowTelemetryResponse {
        try await perform(EnphaseEndpoints.energyExportTelemetry(systemID: systemID))
    }

    func fetchBatteryToday(systemID: Int) async throws -> EnphaseBatteryTelemetryResponse {
        try await perform(EnphaseEndpoints.batteryTelemetry(systemID: systemID))
    }

    private func perform<T: Decodable>(_ url: URL) async throws -> T {
        await throttle.acquire()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey(), forHTTPHeaderField: "key")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnphaseClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw EnphaseClientError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
