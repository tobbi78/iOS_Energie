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
import UserNotifications

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
/// Runs a recurring foreground poll loop (`pollInterval`, ported from the macOS sibling's
/// `DashboardModel.startPolling`/`pollOnce`) once signed in. **Foreground only**: like any plain
/// `Task`-based loop, iOS suspends it a few seconds after the app moves to the background — it
/// resumes (and immediately catches up with one refresh) once the app is foregrounded again, but
/// does not wake the app up on its own. True background monitoring — so e.g. the Anlagendruck-
/// Alarm fires even while the app isn't open — would need a widget-like extension sharing the
/// Viessmann Keychain/App Group, analogous to Epic 5 for PV; tracked as a backlog item rather
/// than built here.
@Observable
@MainActor
final class HeatPumpModel {
    private(set) var state: HeatPumpState
    private(set) var currentFeatures: [ViessmannFeatureDTO] = []

    private let settings: ViessmannSettings
    let pressureAlertSettings: HeatPumpPressureAlertSettings
    private let oauthClient: ViessmannOAuthClient
    private let urlSession: URLSession
    private let now: @Sendable () -> Date
    private let modelContext: ModelContext
    /// Hands the latest heat-pump values off to a paired Apple Watch (see BACKLOG.md,
    /// "Zielplattform Apple Watch"). `nil` by default so existing call sites/tests are
    /// unaffected — `ContentView` injects the real instance.
    private let watchSyncService: WatchSyncService?

    /// Bookkeeping for `HeatPumpPressureAlertTracker` between polls — not `@Observable` state,
    /// just carried forward the same way `DashboardModel.pressureAlertState` was on macOS.
    @ObservationIgnored private var pressureAlertState = HeatPumpPressureAlertTracker.State()

    /// How often to poll while the app is in the foreground. Independent of the PV side
    /// (`SolarModel`) — Enphase's own request budget forces a much slower, budget-adaptive
    /// cadence there, but Viessmann has no known fixed limit (see ERKENNTNISSE_MACOS.md), just a
    /// safe-cadence recommendation of 5–15 minutes.
    var pollInterval: TimeInterval = 600
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    /// Fallback wait after a rate limit (HTTP 429) when the response doesn't include a
    /// `Retry-After` header. Ported from the macOS sibling project's `DashboardModel`: a wasted
    /// retry costs one API call, while waiting a full day when the block clears sooner delays
    /// recovery unnecessarily.
    private static let rateLimitFallbackDelay: TimeInterval = 3600

    init(
        settings: ViessmannSettings,
        modelContext: ModelContext,
        pressureAlertSettings: HeatPumpPressureAlertSettings,
        oauthClient: ViessmannOAuthClient = ViessmannOAuthClient(),
        urlSession: URLSession = .shared,
        watchSyncService: WatchSyncService? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.modelContext = modelContext
        self.pressureAlertSettings = pressureAlertSettings
        self.oauthClient = oauthClient
        self.urlSession = urlSession
        self.watchSyncService = watchSyncService
        self.now = now
        state = HeatPumpModel.initialState(settings: settings)
    }

    /// Read-only access for the settings screen (HP-4) — credentials stay owned by `settings`.
    var credentials: ViessmannCredentials { settings.credentials }
    var deviceSelection: ViessmannDeviceSelection? { settings.deviceSelection }

    /// Clears the current session and deletes all locally stored efficiency history, matching
    /// the deletion mechanism the privacy policy promises ("Trennen der Konto-Verbindung" — see
    /// docs/privacy.html, "Rechte der betroffenen Person"). Deliberately keeps credentials and
    /// the resolved device selection, since those are tied to the Viessmann API
    /// client/installation, not the OAuth session.
    func signOut() {
        stopPolling()
        settings.setTokens(nil)
        // Fetch-then-delete rather than the batch `delete(model:)` API: that batch delete only
        // reaches rows already flushed to the store, missing a just-inserted (not yet
        // autosaved) snapshot from the most recent poll.
        (try? modelContext.fetch(FetchDescriptor<HeatPumpEfficiencySample>()))?.forEach(modelContext.delete)
        currentFeatures = []
        state = .needsSignIn
    }

    func saveCredentials(clientID: String) {
        stopPolling()
        settings.setCredentials(clientID: clientID)
        // A changed Client-ID needs a fresh OAuth session, same reasoning as SolarModel's
        // saveCredentials.
        settings.setTokens(nil)
        state = .needsSignIn
    }

    /// Runs once when the heat-pump section first appears, then keeps polling (see the class
    /// doc comment on the foreground-only caveat).
    func start() async {
        guard settings.credentials.isComplete, settings.tokens != nil else {
            state = HeatPumpModel.initialState(settings: settings)
            return
        }
        // Requested here too, not just in SolarModel.start() (F5.5) — permission is app-wide and
        // UNUserNotificationCenter no-ops once already determined, but the heat pump's pressure
        // alert must work even if PV isn't configured at all.
        await NotificationAuthorization.requestIfNeeded()
        startPolling()
    }

    /// Starts (or restarts) the recurring poll loop. Safe to call repeatedly — cancels any
    /// previous loop first, so a second call never results in two loops running at once.
    func startPolling() {
        stopPolling()
        pollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let delay = await self.refresh()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
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
            let (authorizationURL, pkce, oauthState) = oauthClient.makeAuthorizationRequest(clientID: settings.credentials.clientID)
            let callbackURL = try await webAuthenticationSession.authenticate(
                using: authorizationURL,
                callbackURLScheme: ViessmannEndpoints.callbackScheme
            )
            let tokens = try await oauthClient.completeSignIn(
                callbackURL: callbackURL,
                clientID: settings.credentials.clientID,
                codeVerifier: pkce.codeVerifier,
                state: oauthState
            )
            settings.setTokens(tokens)
            startPolling()
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    /// Fetches all features for the resolved device and captures the efficiency snapshots
    /// (HeatPumpEfficiencySample) derived from them. Returns how long the poll loop should wait
    /// before the next attempt — `pollInterval` normally, or the rate-limit delay when limited —
    /// so `startPolling()`'s loop can space out requests without a fixed, possibly-too-fast timer.
    @discardableResult
    func refresh() async -> TimeInterval {
        state = .loading
        do {
            let client = makeClient()
            let selection = try await resolveDeviceSelection(client: client)
            let features = try await client.fetchFeatures(
                installationID: selection.installationID,
                gatewaySerial: selection.gatewaySerial,
                deviceID: selection.deviceID
            )
            // Wrapped in `withAnimation` so `MetricCard`'s `.contentTransition(.numericText())`
            // actually has an animated transaction to interpolate across (F10.4) — a plain
            // assignment updates the KPI text instantly, with no transition at all.
            withAnimation(.default) {
                currentFeatures = features
            }
            let timestamp = now()
            captureEfficiencySnapshots(features: features, timestamp: timestamp)
            checkPressureAlert(features: features, timestamp: timestamp)
            state = .ready
            watchSyncService?.updateHeatPump(WatchSyncService.HeatPumpUpdate(
                pressureBar: features.numericValue("heating.sensors.pressure.supply"),
                outsideTemperatureCelsius: features.numericValue("heating.sensors.temperature.outside"),
                pressureAlertActive: pressureAlertSettings.isEnabled && pressureAlertState.isBelowThreshold,
                fetchedAt: timestamp
            ))
            return pollInterval
        } catch ViessmannClientError.rateLimited(let retryAfter) {
            let delay = retryAfter ?? Self.rateLimitFallbackDelay
            state = .rateLimited(resumeAt: now().addingTimeInterval(delay))
            return delay
        } catch ViessmannClientError.unauthorized {
            signOut()
            return pollInterval
        } catch {
            state = .error(error.localizedDescription)
            return pollInterval
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

    /// Checks the current supply pressure against `pressureAlertSettings` and schedules a local
    /// notification if a drop, repeat reminder, or recovery is due. Ported from the macOS
    /// sibling project's `DashboardModel.checkPressureAlert`, swapping the iMessage send for a
    /// local notification (no recipient to misconfigure on iOS).
    private func checkPressureAlert(features: [ViessmannFeatureDTO], timestamp: Date) {
        guard pressureAlertSettings.isEnabled else { return }

        let currentPressure = features.numericValue("heating.sensors.pressure.supply")
        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: currentPressure,
            threshold: pressureAlertSettings.threshold,
            now: timestamp,
            state: pressureAlertState,
            recoveryEnabled: pressureAlertSettings.recoveryMessageEnabled,
            repeatInterval: pressureAlertSettings.repeatInterval
        )
        pressureAlertState = newState

        guard let alert, let currentPressure else { return }
        notifyPressureAlert(alert, pressure: currentPressure)
    }

    private func notifyPressureAlert(_ alert: HeatPumpPressureAlertKind, pressure: Double) {
        let pressureText = pressure.formatted(.number.precision(.fractionLength(1...2)))
        let content = UNMutableNotificationContent()
        content.sound = .default
        switch alert {
        case .drop, .repeatReminder:
            let thresholdText = pressureAlertSettings.threshold.formatted(.number.precision(.fractionLength(1...2)))
            content.title = "Wärmepumpe: Anlagendruck zu niedrig"
            content.body = "\(pressureText) bar, Schwellwert \(thresholdText) bar."
        case .recovery:
            content.title = "Wärmepumpe: Anlagendruck wieder normal"
            content.body = "\(pressureText) bar."
        }
        let request = UNNotificationRequest(identifier: "heatPump.pressureAlert", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        do {
            let refreshed = try await oauthClient.refresh(tokens: tokens, clientID: settings.credentials.clientID)
            return settings.adoptRefreshedTokens(refreshed, previousRefreshToken: tokens.refreshToken).accessToken
        } catch {
            // The refresh token may already be stale if the widget extension refreshed
            // concurrently and rotated it first (F9.6 security review, 2026-10-05) — before
            // failing, check whether it already wrote fresher tokens we can use instead.
            if let reloaded = settings.reloadTokensFromStore(), !reloaded.isExpired(now: now()) {
                return reloaded.accessToken
            }
            throw error
        }
    }
}
