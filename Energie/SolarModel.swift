//
//  SolarModel.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import AuthenticationServices
import Foundation
import SwiftData
import SwiftUI

enum SolarError: Error, LocalizedError {
    case signInRequired

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Bitte zuerst mit Enphase anmelden."
        }
    }
}

enum SolarState: Equatable {
    case needsCredentials
    case needsSignIn
    case loading
    case ready
    case error(String)
}

/// Coordinates Enphase auth + polling for the PV section, independent of any other future data
/// source (see BACKLOG.md, "Übertragbares Architekturmuster": one model per source, own state,
/// own poll loop — a heat pump model would be a sibling, not a shared "DashboardModel").
///
/// This first slice only polls once per explicit call (button/appear), not on a recurring
/// schedule — the background/widget refresh strategy (Epic 5 F5.1) is a later branch.
@Observable
@MainActor
final class SolarModel {
    private(set) var state: SolarState
    private(set) var today: PVDailySample?

    private let settings: EnphaseSettings
    private let oauthClient: EnphaseOAuthClient
    private let throttle: EnphaseRequestThrottle
    private let urlSession: URLSession
    private let now: @Sendable () -> Date
    private let modelContext: ModelContext

    init(
        settings: EnphaseSettings,
        modelContext: ModelContext,
        oauthClient: EnphaseOAuthClient = EnphaseOAuthClient(),
        throttle: EnphaseRequestThrottle = EnphaseRequestThrottle(),
        urlSession: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.modelContext = modelContext
        self.oauthClient = oauthClient
        self.throttle = throttle
        self.urlSession = urlSession
        self.now = now
        state = SolarModel.initialState(settings: settings)
    }

    private static func initialState(settings: EnphaseSettings) -> SolarState {
        guard settings.credentials.isComplete else { return .needsCredentials }
        guard settings.tokens != nil else { return .needsSignIn }
        return .loading
    }

    func saveCredentials(clientID: String, clientSecret: String, apiKey: String) {
        settings.setCredentials(clientID: clientID, clientSecret: clientSecret, apiKey: apiKey)
        state = settings.tokens == nil ? .needsSignIn : .loading
    }

    /// Runs the OAuth authorization-code flow via SwiftUI's `WebAuthenticationSession` and, on
    /// success, immediately performs the first poll.
    func signIn(using webAuthenticationSession: WebAuthenticationSession) async {
        guard settings.credentials.isComplete else {
            state = .needsCredentials
            return
        }

        state = .loading
        do {
            let authorizationURL = oauthClient.authorizationURL(clientID: settings.credentials.clientID)
            let callbackURL = try await webAuthenticationSession.authenticate(
                using: authorizationURL,
                callbackURLScheme: EnphaseEndpoints.callbackScheme
            )
            let tokens = try await oauthClient.completeSignIn(callbackURL: callbackURL, credentials: settings.credentials)
            settings.setTokens(tokens)
            await refresh()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Fetches today's values from Enphase and upserts the local `PVDailySample` for today.
    func refresh() async {
        state = .loading
        do {
            let client = try makeClient()
            let systemID = try await resolveSystemID(client: client)

            async let summary = client.fetchSummary(systemID: systemID)
            async let consumption = client.fetchConsumptionToday(systemID: systemID)
            async let imported = client.fetchImportedEnergyToday(systemID: systemID)
            async let exported = client.fetchExportedEnergyToday(systemID: systemID)
            async let battery = client.fetchBatteryToday(systemID: systemID)

            let sample = try await PVDailySample(
                date: Calendar.current.startOfDay(for: now()),
                producedWh: summary.energyTodayWh,
                consumedWh: consumption.totalWh,
                importedWh: imported.totalWh,
                exportedWh: exported.totalWh,
                batterySocPercent: battery.latestSocPercent,
                batteryChargedWh: battery.totalChargedWh,
                batteryDischargedWh: battery.totalDischargedWh
            )

            upsertToday(sample)
            today = sample
            state = .ready
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func upsertToday(_ sample: PVDailySample) {
        let startOfDay = sample.date
        let descriptor = FetchDescriptor<PVDailySample>(
            predicate: #Predicate { $0.date == startOfDay }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.producedWh = sample.producedWh
            existing.consumedWh = sample.consumedWh
            existing.importedWh = sample.importedWh
            existing.exportedWh = sample.exportedWh
            existing.batterySocPercent = sample.batterySocPercent
            existing.batteryChargedWh = sample.batteryChargedWh
            existing.batteryDischargedWh = sample.batteryDischargedWh
        } else {
            modelContext.insert(sample)
        }
    }

    private func resolveSystemID(client: EnphaseClient) async throws -> Int {
        if let systemID = settings.systemID {
            return systemID
        }
        let systems = try await client.fetchSystems()
        guard let first = systems.first else {
            throw EnphaseClientError.invalidResponse
        }
        settings.setSystemID(first.systemID)
        return first.systemID
    }

    private func makeClient() throws -> EnphaseClient {
        // Captured now (on the main actor) rather than read inside the @Sendable closure below,
        // which may run off the main actor and cannot access `settings` directly.
        let apiKey = settings.credentials.apiKey
        return EnphaseClient(
            urlSession: urlSession,
            throttle: throttle,
            apiKey: { apiKey },
            accessToken: { [self] in try await self.validAccessToken() }
        )
    }

    private func validAccessToken() async throws -> String {
        guard let tokens = settings.tokens else {
            throw SolarError.signInRequired
        }
        guard tokens.isExpired(now: now()) else {
            return tokens.accessToken
        }
        let refreshed = try await oauthClient.refresh(tokens: tokens, credentials: settings.credentials)
        settings.setTokens(refreshed)
        return refreshed.accessToken
    }
}
