//
//  HeatPumpModel.swift
//  Energie
//
//  Created by Tobias Florian on 03.10.26.
//

import AuthenticationServices
import Foundation
import SwiftData
import SwiftUI

enum HeatPumpError: Error, LocalizedError {
    case signInRequired

    var errorDescription: String? {
        switch self {
        case .signInRequired:
            return "Bitte zuerst mit Viessmann anmelden."
        }
    }
}

enum HeatPumpState: Equatable {
    case needsCredentials
    case needsSignIn
    case loading
    case ready
    case rateLimited(resumeAt: Date)
    case error(String)
}

/// Coordinates Viessmann auth + polling for the heat-pump section, independent of `SolarModel`
/// (see Plans/Waermepumpe-Integration.md, Abschnitt 3: one model per source, own state, own
/// poll — a failure here must never affect the PV side and vice versa).
///
/// Like `SolarModel`'s first slice, this only polls once per explicit call (button/appear), not
/// on a recurring schedule — a continuous poll loop (`pollInterval`, ported from the macOS
/// sibling's `DashboardModel`) is a later enhancement once the overview screen (HP-3) exists to
/// actually show the result of a background refresh.
@Observable
@MainActor
final class HeatPumpModel {
    private(set) var state: HeatPumpState
    private(set) var currentFeatures: [ViessmannFeatureDTO] = []

    private let settings: ViessmannSettings
    private let oauthClient: ViessmannOAuthClient
    private let urlSession: URLSession
    private let now: @Sendable () -> Date
    private let modelContext: ModelContext

    /// Fallback wait after a rate limit (HTTP 429) when the response doesn't include a
    /// `Retry-After` header. Ported from the macOS sibling project's `DashboardModel`: a wasted
    /// retry costs one API call, while waiting a full day when the block clears sooner delays
    /// recovery unnecessarily.
    private static let rateLimitFallbackDelay: TimeInterval = 3600

    init(
        settings: ViessmannSettings,
        modelContext: ModelContext,
        oauthClient: ViessmannOAuthClient = ViessmannOAuthClient(),
        urlSession: URLSession = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.modelContext = modelContext
        self.oauthClient = oauthClient
        self.urlSession = urlSession
        self.now = now
        state = HeatPumpModel.initialState(settings: settings)
    }

    /// Read-only access for the settings screen (HP-4) — credentials stay owned by `settings`.
    var credentials: ViessmannCredentials { settings.credentials }
    var deviceSelection: ViessmannDeviceSelection? { settings.deviceSelection }

    /// Clears the current session so the next appearance shows the sign-in prompt again.
    /// Deliberately keeps credentials and the resolved device selection, since those are tied to
    /// the Viessmann API client/installation, not the OAuth session.
    func signOut() {
        settings.setTokens(nil)
        currentFeatures = []
        state = .needsSignIn
    }

    func saveCredentials(clientID: String) {
        settings.setCredentials(clientID: clientID)
        // A changed Client-ID needs a fresh OAuth session, same reasoning as SolarModel's
        // saveCredentials.
        settings.setTokens(nil)
        state = .needsSignIn
    }

    /// Runs once when the heat-pump section first appears.
    func start() async {
        guard settings.credentials.isComplete, settings.tokens != nil else {
            state = HeatPumpModel.initialState(settings: settings)
            return
        }
        await refresh()
    }

    private static func initialState(settings: ViessmannSettings) -> HeatPumpState {
        guard settings.credentials.isComplete else { return .needsCredentials }
        guard settings.tokens != nil else { return .needsSignIn }
        return .loading
    }

    /// Runs the OAuth2 PKCE authorization-code flow via SwiftUI's `WebAuthenticationSession` and,
    /// on success, immediately performs the first poll.
    func signIn(using webAuthenticationSession: WebAuthenticationSession) async {
        guard settings.credentials.isComplete else {
            state = .needsCredentials
            return
        }

        state = .loading
        do {
            let (authorizationURL, pkce) = oauthClient.makeAuthorizationRequest(clientID: settings.credentials.clientID)
            let callbackURL = try await webAuthenticationSession.authenticate(
                using: authorizationURL,
                callbackURLScheme: ViessmannEndpoints.callbackScheme
            )
            let tokens = try await oauthClient.completeSignIn(
                callbackURL: callbackURL,
                clientID: settings.credentials.clientID,
                codeVerifier: pkce.codeVerifier
            )
            settings.setTokens(tokens)
            await refresh()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Fetches all features for the resolved device and captures the efficiency snapshots
    /// (HeatPumpEfficiencySample) derived from them.
    func refresh() async {
        state = .loading
        do {
            let client = makeClient()
            let selection = try await resolveDeviceSelection(client: client)
            let features = try await client.fetchFeatures(
                installationID: selection.installationID,
                gatewaySerial: selection.gatewaySerial,
                deviceID: selection.deviceID
            )
            currentFeatures = features
            captureEfficiencySnapshots(features: features, timestamp: now())
            state = .ready
        } catch ViessmannClientError.rateLimited(let retryAfter) {
            state = .rateLimited(resumeAt: now().addingTimeInterval(retryAfter ?? Self.rateLimitFallbackDelay))
        } catch ViessmannClientError.unauthorized {
            signOut()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func resolveDeviceSelection(client: ViessmannClient) async throws -> ViessmannDeviceSelection {
        if let selection = settings.deviceSelection {
            return selection
        }
        let resolved = try await client.resolveDefaultDeviceSelection()
        settings.setDeviceSelection(resolved)
        return resolved
    }

    /// `.day`/`.week` are upserted on every poll — their Viessmann value keeps climbing until the
    /// window rolls over. `.month`/`.year` are captured once, at the first poll after their
    /// boundary (`HeatPumpEfficiencyTracker`). Ported from the macOS sibling's
    /// `DashboardModel.captureEnergySnapshots`.
    private func captureEfficiencySnapshots(features: [ViessmannFeatureDTO], timestamp: Date) {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: timestamp)

        for period in [HeatPumpEfficiencyPeriod.day, .week] {
            upsertContinuousSample(period: period, features: features, todayStart: todayStart)
        }

        var lastDates: [HeatPumpEfficiencyPeriod: Date] = [:]
        for period in [HeatPumpEfficiencyPeriod.month, .year] {
            let rawValue = period.rawValue
            var descriptor = FetchDescriptor<HeatPumpEfficiencySample>(
                predicate: #Predicate { $0.period == rawValue }
            )
            descriptor.sortBy = [SortDescriptor(\.boundaryDate, order: .reverse)]
            descriptor.fetchLimit = 1
            if let latest = try? modelContext.fetch(descriptor).first {
                lastDates[period] = latest.boundaryDate
            }
        }

        let periodsToSnapshot = HeatPumpEfficiencyTracker.periodsNeedingSnapshot(now: timestamp, lastSnapshotDates: lastDates)
        for period in periodsToSnapshot {
            let totals = energyTotals(period: period, features: features)
            modelContext.insert(HeatPumpEfficiencySample(
                period: period,
                boundaryDate: timestamp,
                consumedKWh: totals.consumed,
                producedKWh: totals.produced
            ))
        }
    }

    private func upsertContinuousSample(period: HeatPumpEfficiencyPeriod, features: [ViessmannFeatureDTO], todayStart: Date) {
        let rawValue = period.rawValue
        var descriptor = FetchDescriptor<HeatPumpEfficiencySample>(
            predicate: #Predicate { $0.period == rawValue && $0.boundaryDate == todayStart }
        )
        descriptor.fetchLimit = 1

        let totals = energyTotals(period: period, features: features)
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.consumedKWh = totals.consumed
            existing.producedKWh = totals.produced
        } else {
            modelContext.insert(HeatPumpEfficiencySample(
                period: period,
                boundaryDate: todayStart,
                consumedKWh: totals.consumed,
                producedKWh: totals.produced
            ))
        }
    }

    private func energyTotals(period: HeatPumpEfficiencyPeriod, features: [ViessmannFeatureDTO]) -> (consumed: Double, produced: Double) {
        let consumed = HeatPumpEfficiencyDataSource.sum(
            features: features,
            featureNames: HeatPumpEfficiencyDataSource.consumptionFeatures,
            property: period.sourceProperty
        )
        let produced = HeatPumpEfficiencyDataSource.sum(
            features: features,
            featureNames: HeatPumpEfficiencyDataSource.productionFeatures,
            property: period.sourceProperty
        )
        return (consumed, produced)
    }

    private func makeClient() -> ViessmannClient {
        ViessmannClient(urlSession: urlSession, accessToken: { [self] in try await self.validAccessToken() })
    }

    private func validAccessToken() async throws -> String {
        guard let tokens = settings.tokens else {
            throw HeatPumpError.signInRequired
        }
        guard tokens.isExpired(now: now()) else {
            return tokens.accessToken
        }
        let refreshed = try await oauthClient.refresh(tokens: tokens, clientID: settings.credentials.clientID)
        settings.setTokens(refreshed)
        return refreshed.accessToken
    }
}
