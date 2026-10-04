//
//  EnphaseRequestBudget.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import CloudKit
import Foundation

/// Persistent per-calendar-month request counter (F4.2).
///
/// 1000/month is the confirmed quota for the booked Enphase plan (verified by the user against
/// the Enphase developer portal, see BACKLOG.md), enforced here so the app has a defined,
/// predictable behavior instead of silently exceeding it and finding out via 429s alone.
///
/// An actor, like `EnphaseRequestThrottle`, since `EnphaseClient` can issue several requests
/// concurrently (`async let` in `SolarModel`) and a plain read-increment-write on `UserDefaults`
/// would otherwise be racy.
///
/// Instantiated with `SharedAppGroup.userDefaults` so the widget extension's independent copy
/// of this file (`EnergieWidget/EnphaseRequestBudget.swift` — separate target/module, see that
/// file's header comment) shares the same budget. Keep both copies byte-identical.
actor EnphaseRequestBudget {
    static let monthlyLimit = 1000

    private let userDefaults: UserDefaults
    private let now: @Sendable () -> Date
    private static let monthKey = "EnphaseRequestBudget.month"
    private static let countKey = "EnphaseRequestBudget.count"

    /// Epic 0, F0.4: cross-device coordination for this same counter — see
    /// `syncWithCloudIfAvailable()`.
    private static let cloudKitContainerIdentifier = "iCloud.de.florian.tobias.Energie"
    private static let cloudRecordType = "EnphaseBudgetCounter"
    private static let cloudFieldName = "requestsUsed"

    init(userDefaults: UserDefaults = .standard, now: @escaping @Sendable () -> Date = { Date() }) {
        self.userDefaults = userDefaults
        self.now = now
    }

    /// Requests already recorded in the current calendar month.
    func usedThisMonth() -> Int {
        let currentMonth = monthIdentifier(for: now())
        guard userDefaults.string(forKey: Self.monthKey) == currentMonth else { return 0 }
        return userDefaults.integer(forKey: Self.countKey)
    }

    /// Call once for every request that actually goes out over the network.
    func recordRequest() {
        let currentMonth = monthIdentifier(for: now())
        if userDefaults.string(forKey: Self.monthKey) != currentMonth {
            userDefaults.set(currentMonth, forKey: Self.monthKey)
            userDefaults.set(0, forKey: Self.countKey)
        }
        userDefaults.set(userDefaults.integer(forKey: Self.countKey) + 1, forKey: Self.countKey)
    }

    /// True once the remaining budget for this month (minus `reserve`, kept for the daily
    /// finalize pass) is used up.
    func isExhausted(reserve: Int = 20) -> Bool {
        usedThisMonth() >= Self.monthlyLimit - reserve
    }

    /// Best-effort cross-device reconciliation (Epic 0, F0.4). Several devices (iPhone, iPad,
    /// Mac) could each poll independently and keep their own local count — this merges with the
    /// same CloudKit record every device writes to, taking the higher of the two counts (the
    /// counter only ever increases within a month, so "higher" always means "more requests have
    /// actually gone out somewhere"). Real distributed locking isn't needed at these volumes (max
    /// ~10 requests/minute, poll interval ≥15 minutes) — an occasional, rare double-poll across
    /// two devices in the same interval is an accepted, low-impact risk, not a correctness
    /// requirement (see BACKLOG.md F0.4).
    ///
    /// Call once per polling cycle, **not** per individual request — unlike the purely local
    /// `recordRequest()`/`isExhausted()` checks on the hot per-request gate path, this makes a
    /// network round-trip and must never slow those down. Silently does nothing when CloudKit
    /// is unavailable (no iCloud account, offline, container unreachable); local-only counting
    /// keeps working exactly as before in that case, same fallback principle as `EnergieApp`'s
    /// CloudKit persistence (F0.1).
    func syncWithCloudIfAvailable() async {
        guard FileManager.default.ubiquityIdentityToken != nil else { return }

        let currentMonth = monthIdentifier(for: now())
        let localCount = usedThisMonth()
        let database = CKContainer(identifier: Self.cloudKitContainerIdentifier).privateCloudDatabase
        let recordID = CKRecord.ID(recordName: "enphase-\(currentMonth)")

        do {
            let remoteRecord = try await database.record(for: recordID)
            let remoteCount = remoteRecord[Self.cloudFieldName] as? Int ?? 0
            let merged = max(localCount, remoteCount)
            if merged > localCount {
                adopt(merged, forMonth: currentMonth)
            }
            if merged != remoteCount {
                remoteRecord[Self.cloudFieldName] = merged
                _ = try await database.save(remoteRecord)
            }
        } catch let error as CKError where error.code == .unknownItem {
            let newRecord = CKRecord(recordType: Self.cloudRecordType, recordID: recordID)
            newRecord[Self.cloudFieldName] = localCount
            _ = try? await database.save(newRecord)
        } catch {
            // Best-effort — CloudKit being unreachable must never block polling.
        }
    }

    private func adopt(_ count: Int, forMonth month: String) {
        userDefaults.set(month, forKey: Self.monthKey)
        userDefaults.set(count, forKey: Self.countKey)
    }

    private func monthIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return "\(components.year ?? 0)-\(components.month ?? 0)"
    }
}
