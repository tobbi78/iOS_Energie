//
//  EnphaseRequestThrottleTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 05.10.26.
//

import Foundation
import Testing
@testable import Energie

struct EnphaseRequestThrottleTests {
    @Test func allowsRequestsUpToTheLimitWithoutSleeping() async {
        var sleptFor: [TimeInterval] = []
        let throttle = EnphaseRequestThrottle(
            window: 75,
            limit: 3,
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in sleptFor.append(seconds) }
        )

        await throttle.acquire()
        await throttle.acquire()
        await throttle.acquire()

        #expect(sleptFor.isEmpty)
    }

    @Test func sleepsOnceTheLimitIsReachedWithinTheWindow() async {
        var sleptFor: [TimeInterval] = []
        // Fixed clock — every acquire() happens "at the same instant" as far as the throttle can
        // tell, so the 4th call within a limit of 3 must wait out the full window.
        let throttle = EnphaseRequestThrottle(
            window: 75,
            limit: 3,
            now: { Date(timeIntervalSince1970: 1_000) },
            sleep: { seconds in sleptFor.append(seconds) }
        )

        await throttle.acquire()
        await throttle.acquire()
        await throttle.acquire()
        await throttle.acquire()

        #expect(sleptFor.count == 1)
        #expect(sleptFor.first == 76) // window(75) - elapsed(0) + 1
    }

    @Test func usesTheRealDefaultSleepImplementationWhenNoneIsInjected() async {
        // Every other test here injects a `sleep` closure to stay fast/deterministic — this one
        // exercises the actual default (`Task.sleep`), which production code relies on.
        let throttle = EnphaseRequestThrottle(window: 0.01, limit: 1)
        await throttle.acquire()
        await throttle.acquire()
    }

    @Test func doesNotSleepAgainOnceTheOldestRequestHasAgedOutOfTheWindow() async {
        var sleptFor: [TimeInterval] = []
        var current = Date(timeIntervalSince1970: 1_000)
        let throttle = EnphaseRequestThrottle(
            window: 75,
            limit: 1,
            now: { current },
            sleep: { seconds in sleptFor.append(seconds) }
        )

        await throttle.acquire()
        current = current.addingTimeInterval(100) // well past the 75s window
        await throttle.acquire()

        #expect(sleptFor.isEmpty)
    }
}
