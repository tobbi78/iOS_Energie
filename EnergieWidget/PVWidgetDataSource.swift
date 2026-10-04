//
//  PVWidgetDataSource.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//
//  Deliberately minimal and self-contained (see BACKLOG.md F5.4/F5.6): the widget only shows
//  Produktion/Autarkiegrad, so it only calls the three endpoints needed for that instead of
//  reusing the app's full EnphaseClient (different target/module, see EnphaseRequestBudget.swift
//  for why). It never performs the OAuth sign-in flow itself — only the app does that; the
//  widget just reads whichever access token is currently in the shared Keychain and shows a
//  cached/fallback state if it's missing or expired, rather than trying to refresh it.
//

import Foundation
import Security

/// Reads the same Keychain item the app's `EnphaseKeychainStore` writes. No `kSecAttrAccessGroup`
/// is set explicitly on either side — both targets declare exactly one, matching
/// `keychain-access-groups` entitlement, which the Keychain uses as the implicit default.
private enum PVWidgetKeychain {
    private static let service = "de.florian.tobias.Energie.enphase"

    static func readString(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum PVWidgetDataSource {
    static let sharedDefaults = UserDefaults(suiteName: "group.de.florian.tobias.Energie") ?? .standard

    private static let budget = EnphaseRequestBudget(userDefaults: sharedDefaults)

    /// Mirrors `EnphaseBudgetSettings.reserveKey`/`.defaultReserve` (F6.3) — duplicated as a raw
    /// key string rather than linking that app-only class, same tooling limitation as the other
    /// duplicated files in this target. Keep in sync by hand if the key or default ever changes.
    static var configuredReserve: Int {
        sharedDefaults.object(forKey: "EnphaseBudgetSettings.monthlyReserve") as? Int ?? PVWidgetPollPacing.monthlyReserve
    }
    private static let throttle = EnphaseRequestThrottle()
    private static let baseURL = URL(string: "https://api.enphaseenergy.com")!
    private static let cacheKey = "PVWidgetDataSource.lastSnapshot"

    struct Snapshot: Codable {
        let producedWh: Double
        let selfSufficiencyRate: Double?
        /// Not shown in the widget's own UI (out of scope for F5.4) — fetched only so
        /// `PVWidgetAlerts` can check it for the low-battery notification (F5.5).
        let batterySocPercent: Double?
        let fetchedAt: Date
    }

    enum FetchError: Error {
        case notSignedIn
        case tokenExpired
        case monthlyBudgetExhausted
        case invalidResponse
        case http(Int)
    }

    /// Requests used against the shared monthly budget so far this calendar month — used by
    /// `PVWidgetPollPacing` to decide how long to wait before the next poll (F4.2).
    static func requestsUsedThisMonth() async -> Int {
        await budget.usedThisMonth()
    }

    /// Last successfully fetched snapshot, shown as a fallback when a fresh fetch fails (e.g.
    /// offline, budget exhausted) so the widget degrades gracefully instead of going blank.
    static func cachedSnapshot() -> Snapshot? {
        guard let data = sharedDefaults.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Snapshot.self, from: data)
    }

    static func fetchLatestSnapshot() async -> Result<Snapshot, FetchError> {
        guard let accessToken = PVWidgetKeychain.readString(account: "accessToken"),
              let apiKey = PVWidgetKeychain.readString(account: "apiKey") else {
            return .failure(.notSignedIn)
        }
        if let expiresAtString = PVWidgetKeychain.readString(account: "tokenExpiresAt"),
           let expiresAtInterval = TimeInterval(expiresAtString),
           Date() >= Date(timeIntervalSince1970: expiresAtInterval) {
            return .failure(.tokenExpired)
        }
        guard let systemIDString = PVWidgetKeychain.readString(account: "systemID"),
              let systemID = Int(systemIDString) else {
            return .failure(.notSignedIn)
        }

        guard await !budget.isExhausted(reserve: configuredReserve) else {
            return .failure(.monthlyBudgetExhausted)
        }

        do {
            async let summary: SummaryDTO = perform(
                url: baseURL.appendingPathComponent("api/v4/systems/\(systemID)/summary"),
                accessToken: accessToken, apiKey: apiKey
            )
            async let consumption: MeterTelemetryDTO = perform(
                url: baseURL.appendingPathComponent("api/v4/systems/\(systemID)/telemetry/consumption_meter"),
                accessToken: accessToken, apiKey: apiKey
            )
            async let imported: EnergyFlowDTO = perform(
                url: baseURL.appendingPathComponent("api/v4/systems/\(systemID)/energy_import_telemetry"),
                accessToken: accessToken, apiKey: apiKey
            )
            async let battery: BatteryTelemetryDTO = perform(
                url: baseURL.appendingPathComponent("api/v4/systems/\(systemID)/telemetry/battery"),
                accessToken: accessToken, apiKey: apiKey
            )

            let summaryResponse = try await summary
            let consumedWh = try await consumption.intervals.reduce(0) { $0 + $1.enwh }
            let importedWh = try await imported.intervals.flatMap { $0 }.reduce(0) { $0 + ($1.whImported ?? 0) }
            let selfSufficiencyRate = consumedWh > 0 ? (consumedWh - importedWh) / consumedWh : nil
            let batterySocPercent = try await battery.intervals.last?.soc.percent

            let snapshot = Snapshot(
                producedWh: summaryResponse.energyToday,
                selfSufficiencyRate: selfSufficiencyRate,
                batterySocPercent: batterySocPercent,
                fetchedAt: Date()
            )
            if let data = try? JSONEncoder().encode(snapshot) {
                sharedDefaults.set(data, forKey: cacheKey)
            }
            return .success(snapshot)
        } catch let error as FetchError {
            return .failure(error)
        } catch {
            return .failure(.invalidResponse)
        }
    }

    private struct SummaryDTO: Decodable {
        let energyToday: Double
        enum CodingKeys: String, CodingKey { case energyToday = "energy_today" }
    }

    private struct MeterTelemetryDTO: Decodable {
        struct Interval: Decodable { let enwh: Double }
        let intervals: [Interval]
    }

    private struct EnergyFlowDTO: Decodable {
        struct Entry: Decodable {
            let whImported: Double?
            enum CodingKeys: String, CodingKey { case whImported = "wh_imported" }
        }
        let intervals: [[Entry]]
    }

    private struct BatteryTelemetryDTO: Decodable {
        struct Interval: Decodable {
            struct StateOfCharge: Decodable { let percent: Double }
            let soc: StateOfCharge
        }
        let intervals: [Interval]
    }

    private static func perform<T: Decodable>(url: URL, accessToken: String, apiKey: String) async throws -> T {
        await throttle.acquire()

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "key")

        let (data, response) = try await URLSession.shared.data(for: request)
        await budget.recordRequest()

        guard let httpResponse = response as? HTTPURLResponse else {
            throw FetchError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw FetchError.http(httpResponse.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
