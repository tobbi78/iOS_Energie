//
//  ShellyRequestThrottle.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation

/// Enforces Shelly's account-wide 1-request/second limit (F15.1, `SHELLY_API_WERTE.md`) — unlike
/// Enphase's `EnphaseRequestThrottle` (a sliding window allowing several requests per minute),
/// Shelly's limit is a single request at a time, so tracking just the last request's timestamp is
/// enough; no sliding window of past timestamps is needed.
actor ShellyRequestThrottle {
    /// `ShellyClient` still has no single owning model — `ShellyModel` (F16.1) owns one instance
    /// for polling, but `ShellyDevicesScreen` constructs its own for device verification, so the
    /// throttle itself has to be the shared part, unlike `EnphaseRequestThrottle`/
    /// `EnphaseRequestBudget`, which `SolarModel` owns once and hands to its `EnphaseClient`.
    static let shared = ShellyRequestThrottle()

    private var lastRequestAt: Date?
    private let window: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        window: TimeInterval = 1,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.window = window
        self.now = now
        self.sleep = sleep
    }

    /// Suspends until at least `window` seconds have passed since the last acquired request,
    /// then records this one.
    func acquire() async {
        if let lastRequestAt {
            let waitTime = window - now().timeIntervalSince(lastRequestAt)
            if waitTime > 0 {
                await sleep(waitTime)
            }
        }
        lastRequestAt = now()
    }
}
