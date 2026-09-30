//
//  EnphaseRequestThrottle.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation

/// Sliding-window minute throttle for Enphase requests.
///
/// Enphase limits to ~10 requests/minute (see ENPHASE_API_WERTE.md). 75s instead of a literal
/// 60s window is a deliberate safety margin — the same value the macOS sibling project settled
/// on after real-world testing (see ERKENNTNISSE_MACOS.md).
///
/// This is the minimal per-minute guardrail only. The full monthly-budget management (Epic 4 in
/// BACKLOG.md) is a separate, later branch — this actor is written so it can be reused there.
actor EnphaseRequestThrottle {
    private var requestTimestamps: [Date] = []
    private let window: TimeInterval
    private let limit: Int
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async -> Void

    init(
        window: TimeInterval = 75,
        limit: Int = 10,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.window = window
        self.limit = limit
        self.now = now
        self.sleep = sleep
    }

    /// Suspends until it is safe to issue another request, then records it.
    func acquire() async {
        prune()
        if requestTimestamps.count >= limit, let oldest = requestTimestamps.first {
            let waitTime = window - now().timeIntervalSince(oldest) + 1
            if waitTime > 0 {
                await sleep(waitTime)
            }
            prune()
        }
        requestTimestamps.append(now())
    }

    private func prune() {
        let cutoff = now().addingTimeInterval(-window)
        requestTimestamps.removeAll { $0 < cutoff }
    }
}
