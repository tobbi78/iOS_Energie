//
//  PVWidgetPollPacingTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 05.10.26.
//

import Foundation
import Testing
@testable import Energie

struct PVWidgetPollPacingTests {

    // MARK: - shouldReuseCachedSnapshot

    @Test func reusesACacheYoungerThanTheMinimumInterval() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let now = fetchedAt.addingTimeInterval(PVWidgetPollPacing.minimumInterval - 1)
        #expect(PVWidgetPollPacing.shouldReuseCachedSnapshot(fetchedAt: fetchedAt, now: now))
    }

    @Test func doesNotReuseACacheAtOrPastTheMinimumInterval() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let now = fetchedAt.addingTimeInterval(PVWidgetPollPacing.minimumInterval)
        #expect(!PVWidgetPollPacing.shouldReuseCachedSnapshot(fetchedAt: fetchedAt, now: now))
    }

    @Test func doesNotReuseAnOldCache() {
        let fetchedAt = Date(timeIntervalSince1970: 1_000)
        let now = fetchedAt.addingTimeInterval(60 * 60)
        #expect(!PVWidgetPollPacing.shouldReuseCachedSnapshot(fetchedAt: fetchedAt, now: now))
    }

    // MARK: - nextPollDelay

    @Test func spreadsTheRemainingBudgetEvenlyOverTheRestOfTheMonth() {
        // 1. Januar, Monat hat 31 Tage. 100 nutzbare Requests / 4 pro Poll = 25 verbleibende
        // Polls, verteilt auf die restliche Zeit bis zum 1. Februar.
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let delay = PVWidgetPollPacing.nextPollDelay(usedThisMonth: 880, monthlyLimit: 1000, reserve: 20, now: now)
        let monthEnd = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        let expected = monthEnd.timeIntervalSince(now) / Double((1000 - 20 - 880) / PVWidgetPollPacing.requestsPerPoll)
        #expect(delay == expected)
    }

    @Test func fallsBackWhenTheBudgetIsAlreadyUsedUp() {
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let delay = PVWidgetPollPacing.nextPollDelay(usedThisMonth: 990, monthlyLimit: 1000, reserve: 20, now: now)
        #expect(delay == PVWidgetPollPacing.fallbackInterval)
    }

    @Test func neverPollsMoreOftenThanTheMinimumInterval() {
        // Fast der ganze Monat ist schon vorbei, aber noch viel Budget übrig -> die Formel
        // würde ein sehr kurzes Intervall vorschlagen, das hier gedeckelt werden muss.
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 23, minute: 0))!
        let delay = PVWidgetPollPacing.nextPollDelay(usedThisMonth: 0, monthlyLimit: 1000, reserve: 20, now: now)
        #expect(delay == PVWidgetPollPacing.minimumInterval)
    }
}
