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
import UserNotifications

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

/// The five `_lifetime` series, re-keyed by calendar day for easy lookup during backfill/finalize.
private struct LifetimeDailyMaps {
    var produced: [Date: Double] = [:]
    var consumed: [Date: Double] = [:]
    var imported: [Date: Double] = [:]
    var exported: [Date: Double] = [:]
    var charged: [Date: Double] = [:]
    var discharged: [Date: Double] = [:]
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
    private let budgetSettings: EnphaseBudgetSettings
    private let oauthClient: EnphaseOAuthClient
    private let throttle: EnphaseRequestThrottle
    private let budget: EnphaseRequestBudget
    private let urlSession: URLSession
    private let now: @Sendable () -> Date
    private let modelContext: ModelContext
    private let userDefaults: UserDefaults

    private static let lastFinalizeRunDayKey = "SolarModel.lastFinalizeRunDay"

    init(
        settings: EnphaseSettings,
        modelContext: ModelContext,
        budgetSettings: EnphaseBudgetSettings,
        oauthClient: EnphaseOAuthClient = EnphaseOAuthClient(),
        throttle: EnphaseRequestThrottle = EnphaseRequestThrottle(),
        budget: EnphaseRequestBudget = EnphaseRequestBudget(),
        urlSession: URLSession = .shared,
        userDefaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.settings = settings
        self.modelContext = modelContext
        self.budgetSettings = budgetSettings
        self.oauthClient = oauthClient
        self.throttle = throttle
        self.budget = budget
        self.urlSession = urlSession
        self.userDefaults = userDefaults
        self.now = now
        state = SolarModel.initialState(settings: settings)
    }

    /// Requests already used against the monthly budget this calendar month (F4.4).
    func requestsUsedThisMonth() async -> Int {
        await budget.usedThisMonth()
    }

    /// Read-only access for the settings screen (F6.1) — credentials stay owned by `settings`.
    var credentials: EnphaseCredentials { settings.credentials }
    var systemID: Int? { settings.systemID }

    /// Clears the current session so the next appearance shows the sign-in prompt again.
    /// Deliberately keeps credentials/system info, since those are tied to the Enphase
    /// developer app/installation, not the OAuth session.
    func signOut() {
        settings.setTokens(nil)
        today = nil
        state = .needsSignIn
    }

    /// Runs once when the PV section first appears: polls today's live values first, then
    /// backfills missing history and finalizes past days in the background (F3.2/F3.3).
    ///
    /// Order matters here: `refresh()` alone never needs more than ~6 requests (system lookup +
    /// 5 "today" endpoints), comfortably under the shared minute throttle. Backfill and finalize
    /// can each add 5 more — on a first run or after a multi-day gap that easily exceeds the
    /// throttle's limit, which makes it deliberately *sleep* for up to ~75s before the
    /// over-the-limit request goes out (see `EnphaseRequestThrottle`). Running `refresh()` first
    /// means the screen already shows today's values before that sleep can happen, instead of
    /// the whole screen being stuck on the loading spinner for it.
    func start() async {
        guard settings.credentials.isComplete, settings.tokens != nil else {
            state = SolarModel.initialState(settings: settings)
            return
        }
        await requestNotificationAuthorizationIfNeeded()
        await refresh()
        await backfillMissingDaysIfNeeded()
        await runDailyFinalizeIfNeeded()
        pruneOldDailySamplesIfNeeded()
    }

    /// The widget extension schedules the actual alerts (F5.5) — it's the process that polls
    /// regularly in the background, so it's the one that can actually notice an outage/low
    /// battery/exhausted budget while the user isn't looking at the app. Extensions share their
    /// containing app's notification permission (no separate Settings entry of their own), so
    /// this request — made here, where there's a foreground app to show the system prompt —
    /// covers both.
    private func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let notificationSettings = await center.notificationSettings()
        guard notificationSettings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    private static func initialState(settings: EnphaseSettings) -> SolarState {
        guard settings.credentials.isComplete else { return .needsCredentials }
        guard settings.tokens != nil else { return .needsSignIn }
        return .loading
    }

    func saveCredentials(clientID: String, clientSecret: String, apiKey: String) {
        settings.setCredentials(clientID: clientID, clientSecret: clientSecret, apiKey: apiKey)
        // A changed client/secret needs a fresh OAuth session regardless of whether one already
        // existed — also avoids leaving `state` stuck on `.loading` with nothing to resolve it
        // (previously unreachable from the sign-in-less credentials form, but reachable now that
        // the settings screen (F6.1) can save credentials while already signed in).
        settings.setTokens(nil)
        state = .needsSignIn
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
        // Re-fetches once even if `systemID` is already cached, as long as `operationalAt` is
        // still unknown — covers a settings cache written before that field existed (see
        // BACKLOG.md "Komplette Historie statt 30-Tage-Fenster").
        if let systemID = settings.systemID, settings.operationalAt != nil {
            return systemID
        }
        let systems = try await client.fetchSystems()
        guard let first = systems.first else {
            throw EnphaseClientError.invalidResponse
        }
        settings.setSystemID(first.systemID)
        if let operationalAt = first.operationalAt {
            settings.setOperationalAt(Date(timeIntervalSince1970: TimeInterval(operationalAt)))
        }
        return first.systemID
    }

    /// Fetches and re-keys the five `_lifetime` series by calendar day (F3.2/F3.3).
    private func fetchLifetimeMaps(client: EnphaseClient, systemID: Int, startDate: Date) async throws -> LifetimeDailyMaps {
        async let energy = client.fetchEnergyLifetime(systemID: systemID, startDate: startDate)
        async let consumption = client.fetchConsumptionLifetime(systemID: systemID, startDate: startDate)
        async let imported = client.fetchImportLifetime(systemID: systemID, startDate: startDate)
        async let exported = client.fetchExportLifetime(systemID: systemID, startDate: startDate)
        async let battery = client.fetchBatteryLifetime(systemID: systemID, startDate: startDate)

        let energyResponse = try await energy
        let consumptionResponse = try await consumption
        let importResponse = try await imported
        let exportResponse = try await exported
        let batteryResponse = try await battery

        var maps = LifetimeDailyMaps()
        for entry in energyResponse.dailyValues { maps.produced[entry.date] = entry.value }
        for entry in consumptionResponse.dailyValues { maps.consumed[entry.date] = entry.value }
        for entry in importResponse.dailyValues { maps.imported[entry.date] = entry.value }
        for entry in exportResponse.dailyValues { maps.exported[entry.date] = entry.value }
        for entry in batteryResponse.dailyChargedValues { maps.charged[entry.date] = entry.value }
        for entry in batteryResponse.dailyDischargedValues { maps.discharged[entry.date] = entry.value }
        return maps
    }

    /// Inserts `PVDailySample` rows for any day between the backfill start day and yesterday
    /// that isn't stored locally yet (F3.2). Best-effort: a failure here (e.g. offline) is not
    /// surfaced as an error state — the gap simply remains and is retried on the next start.
    func backfillMissingDaysIfNeeded() async {
        do {
            let client = try makeClient()
            let systemID = try await resolveSystemID(client: client)

            let today = Calendar.current.startOfDay(for: now())
            let startDay = PVBackfillPlanner.backfillStartDay(operationalAt: settings.operationalAt, today: today)
            let existingDays = Set(try modelContext.fetch(FetchDescriptor<PVDailySample>()).map(\.date))
            let missingDays = PVBackfillPlanner.missingDays(existingDays: existingDays, from: startDay, today: today)
            guard !missingDays.isEmpty else { return }

            let maps = try await fetchLifetimeMaps(client: client, systemID: systemID, startDate: startDay)
            for day in missingDays {
                modelContext.insert(
                    PVDailySample(
                        date: day,
                        producedWh: maps.produced[day] ?? 0,
                        consumedWh: maps.consumed[day] ?? 0,
                        importedWh: maps.imported[day] ?? 0,
                        exportedWh: maps.exported[day] ?? 0,
                        batterySocPercent: nil,
                        batteryChargedWh: maps.charged[day] ?? 0,
                        batteryDischargedWh: maps.discharged[day] ?? 0,
                        isFinal: true
                    )
                )
            }
        } catch {
            // Best-effort — see doc comment above.
        }
    }

    /// Once per calendar day, replaces any not-yet-final past day with the final `_lifetime`
    /// values (F3.3). Runs before the live poll in `start()` so "today" never gets finalized.
    func runDailyFinalizeIfNeeded() async {
        let today = Calendar.current.startOfDay(for: now())
        if let lastRun = userDefaults.object(forKey: Self.lastFinalizeRunDayKey) as? Date,
           Calendar.current.isDate(lastRun, inSameDayAs: today) {
            return
        }

        do {
            let nonFinalPastDays = try modelContext.fetch(
                FetchDescriptor<PVDailySample>(predicate: #Predicate { !$0.isFinal && $0.date < today })
            )
            guard let earliestNonFinal = nonFinalPastDays.map(\.date).min() else {
                userDefaults.set(today, forKey: Self.lastFinalizeRunDayKey)
                return
            }

            let client = try makeClient()
            let systemID = try await resolveSystemID(client: client)
            let maps = try await fetchLifetimeMaps(client: client, systemID: systemID, startDate: earliestNonFinal)

            for sample in nonFinalPastDays {
                let produced = maps.produced[sample.date] ?? 0
                let consumed = maps.consumed[sample.date] ?? 0
                let imported = maps.imported[sample.date] ?? 0
                let exported = maps.exported[sample.date] ?? 0

                // Trailing zeros mean Enphase hasn't reported this day yet, not a genuine 0 Wh
                // day (ENPHASE_API_WERTE.md) — leave it non-final and retry on the next run.
                guard produced != 0 || consumed != 0 || imported != 0 || exported != 0 else { continue }

                sample.producedWh = produced
                sample.consumedWh = consumed
                sample.importedWh = imported
                sample.exportedWh = exported
                sample.batteryChargedWh = maps.charged[sample.date] ?? sample.batteryChargedWh
                sample.batteryDischargedWh = maps.discharged[sample.date] ?? sample.batteryDischargedWh
                sample.isFinal = true
            }

            userDefaults.set(today, forKey: Self.lastFinalizeRunDayKey)
        } catch {
            // Best-effort, same reasoning as backfillMissingDaysIfNeeded().
        }
    }

    /// Folds daily rows older than a year into `PVYearlySample` totals and deletes the source
    /// rows (F3.6), so the local database doesn't grow without bound over multi-year use.
    func pruneOldDailySamplesIfNeeded() {
        do {
            let allDailySamples = try modelContext.fetch(FetchDescriptor<PVDailySample>())
            let today = now()
            let oldSamples = allDailySamples.filter { PVHistoryPruner.isEligibleForPruning(date: $0.date, now: today) }
            guard !oldSamples.isEmpty else { return }

            let existingYearlySamples = try modelContext.fetch(FetchDescriptor<PVYearlySample>())
            let calendar = Calendar.current

            for (yearStart, rowsInYear) in PVHistoryPruner.groupByYear(oldSamples, calendar: calendar) {
                let yearEnd = calendar.date(byAdding: .year, value: 1, to: yearStart) ?? yearStart
                let total = PVPeriodAggregation.total(of: rowsInYear, from: yearStart, to: yearEnd, isRunning: false)

                if let existingYear = existingYearlySamples.first(where: { calendar.isDate($0.yearStart, equalTo: yearStart, toGranularity: .year) }) {
                    existingYear.producedWh += total.producedWh
                    existingYear.consumedWh += total.consumedWh
                    existingYear.importedWh += total.importedWh
                    existingYear.exportedWh += total.exportedWh
                    existingYear.batteryChargedWh += total.batteryChargedWh
                    existingYear.batteryDischargedWh += total.batteryDischargedWh
                } else {
                    modelContext.insert(
                        PVYearlySample(
                            yearStart: yearStart,
                            producedWh: total.producedWh,
                            consumedWh: total.consumedWh,
                            importedWh: total.importedWh,
                            exportedWh: total.exportedWh,
                            batteryChargedWh: total.batteryChargedWh,
                            batteryDischargedWh: total.batteryDischargedWh
                        )
                    )
                }

                for row in rowsInYear {
                    modelContext.delete(row)
                }
            }
        } catch {
            // Maintenance task — a failure just means we try again on the next launch.
        }
    }

    private func makeClient() throws -> EnphaseClient {
        // Captured now (on the main actor) rather than read inside the @Sendable closure below,
        // which may run off the main actor and cannot access `settings`/`budgetSettings` directly.
        let apiKey = settings.credentials.apiKey
        let reserve = budgetSettings.monthlyReserve
        return EnphaseClient(
            urlSession: urlSession,
            throttle: throttle,
            budget: budget,
            apiKey: { apiKey },
            accessToken: { [self] in try await self.validAccessToken() },
            reserve: { reserve }
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
