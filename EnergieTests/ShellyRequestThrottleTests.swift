//
//  ShellyRequestThrottleTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

struct ShellyRequestThrottleTests {
    @Test func allowsTheFirstRequestWithoutSleeping() async {
        nonisolated(unsafe) var sleptFor: [TimeInterval] = []
        let throttle = ShellyRequestThrottle(
            window: 1,
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in sleptFor.append(seconds) }
        )

        await throttle.acquire()

        #expect(sleptFor.isEmpty)
    }

    @Test func sleepsForTheRemainderOfTheWindowOnAnImmediateSecondRequest() async {
        nonisolated(unsafe) var sleptFor: [TimeInterval] = []
        // Fixed clock — the second acquire() looks like it happens "at the same instant" as the
        // first, so it must wait out the full window.
        let throttle = ShellyRequestThrottle(
            window: 1,
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in sleptFor.append(seconds) }
        )

        await throttle.acquire()
        await throttle.acquire()

        #expect(sleptFor == [1])
    }

    @Test func doesNotSleepAgainOnceTheWindowHasElapsed() async {
        nonisolated(unsafe) var sleptFor: [TimeInterval] = []
        nonisolated(unsafe) var current = Date(timeIntervalSince1970: 1_000)
        let throttle = ShellyRequestThrottle(
            window: 1,
            now: { current },
            sleep: { seconds in sleptFor.append(seconds) }
        )

        await throttle.acquire()
        current = current.addingTimeInterval(2) // well past the 1s window
        await throttle.acquire()

        #expect(sleptFor.isEmpty)
    }

    @Test func usesTheRealDefaultSleepImplementationWhenNoneIsInjected() async {
        // Every other test here injects a `sleep` closure to stay fast/deterministic — this one
        // exercises the actual default (`Task.sleep`), which production code relies on.
        let throttle = ShellyRequestThrottle(window: 0.01)
        await throttle.acquire()
        await throttle.acquire()
    }
}
