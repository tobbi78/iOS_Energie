//
//  EnphaseClient.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

enum EnphaseClientError: Error, LocalizedError, Equatable {
    case invalidResponse
    case http(status: Int, body: String)
    /// HTTP 429 with a decodable body (F4.3) — more specific than `.http` because it carries
    /// when the limit resets, so callers/UI can say more than just "try again".
    case rateLimited(period: String?, periodEnd: Date?)
    /// The monthly request budget (F4.2) is used up — thrown by `perform(url:)` *before* any
    /// network access, not a response from Enphase.
    case monthlyBudgetExhausted

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Enphase hat eine unerwartete Antwort geschickt."
        case .http(let status, let body):
            return "Enphase-Anfrage fehlgeschlagen (HTTP \(status)): \(body)"
        case .rateLimited(let period, let periodEnd):
            let periodLabel = period == "month" ? "Monats" : "Minuten"
            if let periodEnd {
                return "Enphase-\(periodLabel)-Limit erreicht. Nächster Versuch ab \(periodEnd.formatted(date: .omitted, time: .shortened))."
            }
            return "Enphase-\(periodLabel)-Limit erreicht. Bitte später erneut versuchen."
        case .monthlyBudgetExhausted:
            return "Monatliches Abfrage-Kontingent für Enphase ist erschöpft. Weitere Abrufe sind erst im nächsten Monat wieder möglich."
        }
    }
}

/// Body Enphase sends with HTTP 429 (see ENPHASE_API_WERTE.md): `period` is "minute" or "month".
private struct EnphaseRateLimitErrorBody: Decodable {
    let period: String?
    let periodEnd: Int?

    enum CodingKeys: String, CodingKey {
        case period
        case periodEnd = "period_end"
    }
}

/// Authenticated Enphase API access. Every request carries both required headers
/// (`Authorization: Bearer <token>` and `key: <API key>`, see ENPHASE_API_WERTE.md), is gated by
/// the monthly budget (F4.2) and passes through the shared minute throttle (F4.1) before going
/// out; a successfully sent request is then counted against the budget.
struct EnphaseClient {
    var urlSession: URLSession = .shared
    var throttle: EnphaseRequestThrottle
    var budget: EnphaseRequestBudget
    var apiKey: @Sendable () -> String
    var accessToken: @Sendable () async throws -> String
    /// How much of the monthly budget to hold back (F6.3) — configurable via
    /// `EnphaseBudgetSettings` instead of the previous hardcoded `20`.
    var reserve: @Sendable () -> Int = { EnphaseBudgetSettings.defaultReserve }

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

    // MARK: - Lifetime (daily) series — backfill (F3.2) and daily finalize (F3.3)

    func fetchEnergyLifetime(systemID: Int, startDate: Date? = nil) async throws -> EnphaseEnergyLifetimeResponse {
        try await perform(EnphaseEndpoints.energyLifetime(systemID: systemID, startDate: startDate))
    }

    func fetchConsumptionLifetime(systemID: Int, startDate: Date? = nil) async throws -> EnphaseConsumptionLifetimeResponse {
        try await perform(EnphaseEndpoints.consumptionLifetime(systemID: systemID, startDate: startDate))
    }

    func fetchImportLifetime(systemID: Int, startDate: Date? = nil) async throws -> EnphaseImportLifetimeResponse {
        try await perform(EnphaseEndpoints.energyImportLifetime(systemID: systemID, startDate: startDate))
    }

    func fetchExportLifetime(systemID: Int, startDate: Date? = nil) async throws -> EnphaseExportLifetimeResponse {
        try await perform(EnphaseEndpoints.energyExportLifetime(systemID: systemID, startDate: startDate))
    }

    func fetchBatteryLifetime(systemID: Int, startDate: Date? = nil) async throws -> EnphaseBatteryLifetimeResponse {
        try await perform(EnphaseEndpoints.batteryLifetime(systemID: systemID, startDate: startDate))
    }

    private func perform<T: Decodable>(_ url: URL) async throws -> T {
        guard await !budget.isExhausted(reserve: reserve()) else {
            throw EnphaseClientError.monthlyBudgetExhausted
        }
        await throttle.acquire()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await accessToken())", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey(), forHTTPHeaderField: "key")

        let (data, response) = try await urlSession.data(for: request)
        await budget.recordRequest()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw EnphaseClientError.invalidResponse
        }
        if httpResponse.statusCode == 429 {
            if let rateLimit = try? JSONDecoder().decode(EnphaseRateLimitErrorBody.self, from: data) {
                throw EnphaseClientError.rateLimited(
                    period: rateLimit.period,
                    periodEnd: rateLimit.periodEnd.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            }
            throw EnphaseClientError.http(status: 429, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw EnphaseClientError.http(status: httpResponse.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
