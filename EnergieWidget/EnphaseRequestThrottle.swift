//
//  EnphaseRequestThrottle.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//
//  Intentional duplicate of Energie/Enphase/EnphaseRequestThrottle.swift (separate target,
//  see EnphaseRequestBudget.swift's header comment for why). Unlike the budget, this throttle's
//  state is purely in-memory per process — it does NOT coordinate across the app and widget
//  extension processes, only within whichever one is currently running. A known, accepted gap
//  (BACKLOG.md F5.6): if both happen to poll within the same ~75s window, Enphase's per-minute
//  limit could in theory be exceeded across the two processes even though neither one alone
//  would trip its own throttle. Low risk given each poll is only 2-3 requests and the limit is
//  10/minute; handled gracefully by the 429 path either way.
//

import Foundation

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
