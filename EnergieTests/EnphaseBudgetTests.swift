//
//  EnphaseBudgetTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import Testing
@testable import Energie

private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
}

struct EnphaseBudgetTests {

    @Test func startsAtZeroForANewMonth() async {
        let budget = EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!, now: { date(2026, 9, 30) })
        #expect(await budget.usedThisMonth() == 0)
    }

    @Test func recordRequestIncrementsCount() async {
        let budget = EnphaseRequestBudget(userDefaults: UserDefaults(suiteName: UUID().uuidString)!, now: { date(2026, 9, 30) })
        await budget.recordRequest()
        await budget.recordRequest()
        #expect(await budget.usedThisMonth() == 2)
    }

    @Test func resetsWhenTheCalendarMonthChanges() async {
        var current = date(2026, 9, 30)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let budget = EnphaseRequestBudget(userDefaults: defaults, now: { current })

        await budget.recordRequest()
        #expect(await budget.usedThisMonth() == 1)

        current = date(2026, 10, 1)
        #expect(await budget.usedThisMonth() == 0)

        await budget.recordRequest()
        #expect(await budget.usedThisMonth() == 1)
    }

    @Test func isExhaustedRespectsReserve() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let budget = EnphaseRequestBudget(userDefaults: defaults, now: { date(2026, 9, 30) })

        for _ in 0..<(EnphaseRequestBudget.defaultMonthlyLimit - 20) {
            await budget.recordRequest()
        }

        #expect(await budget.isExhausted(monthlyLimit: EnphaseRequestBudget.defaultMonthlyLimit, reserve: 20))
    }

    @Test func isNotExhaustedBelowTheReserveThreshold() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let budget = EnphaseRequestBudget(userDefaults: defaults, now: { date(2026, 9, 30) })

        for _ in 0..<(EnphaseRequestBudget.defaultMonthlyLimit - 21) {
            await budget.recordRequest()
        }

        #expect(!(await budget.isExhausted(monthlyLimit: EnphaseRequestBudget.defaultMonthlyLimit, reserve: 20)))
    }

    // F6.4: the limit itself is now configurable (e.g. a smaller booked Enphase plan) — must be
    // respected independently of the 1000 default.
    @Test func isExhaustedRespectsALowerConfiguredLimit() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let budget = EnphaseRequestBudget(userDefaults: defaults, now: { date(2026, 9, 30) })

        for _ in 0..<180 {
            await budget.recordRequest()
        }

        #expect(await budget.isExhausted(monthlyLimit: 200, reserve: 20))
        #expect(!(await budget.isExhausted(monthlyLimit: 300, reserve: 20)))
    }

    // MARK: - Error messages (F4.3)

    @Test func rateLimitedErrorDescriptionMentionsPeriodAndResetTime() {
        let periodEnd = date(2026, 10, 1)
        let error = EnphaseClientError.rateLimited(period: "month", periodEnd: periodEnd, detail: nil)
        #expect(error.errorDescription?.contains("Monats") == true)
    }

    @Test func monthlyBudgetExhaustedHasADescription() {
        #expect(EnphaseClientError.monthlyBudgetExhausted.errorDescription != nil)
    }

    @Test func invalidResponseHasADescription() {
        #expect(EnphaseClientError.invalidResponse.errorDescription != nil)
    }

    // F9.4 security review (2026-10-05): the raw response body must never reach the UI, only
    // the status code.
    @Test func httpErrorDescriptionMentionsStatusButNotBody() {
        let error = EnphaseClientError.http(status: 500, body: "boom")
        #expect(error.errorDescription?.contains("500") == true)
        #expect(error.errorDescription?.contains("boom") == false)
    }

    @Test func rateLimitedErrorDescriptionWithoutPeriodEndStillHasOne() {
        let error = EnphaseClientError.rateLimited(period: "minute", periodEnd: nil, detail: nil)
        #expect(error.errorDescription?.contains("Minuten") == true)
    }

    @Test func rateLimitedErrorDescriptionIgnoresEnphasesEnglishDetailWhenPeriodIsUnrecognized() {
        // The real shape observed from a live 429 (2026-10-05 incident, see BACKLOG.md): no
        // `period` field at all, just a plan-level usage-limit message. Must NOT be mislabeled
        // as "Minuten" (the old, incorrect default) — but Enphase's own text is English, so it's
        // not shown to the user directly either; a German generic message is used instead.
        let error = EnphaseClientError.rateLimited(period: nil, periodEnd: nil, detail: "Usage limit exceeded for plan Watt")
        #expect(error.errorDescription == "Enphase-Nutzungslimit erreicht. Bitte später erneut versuchen.")
    }

    @Test func rateLimitedErrorDescriptionFallsBackToAGenericMessageWithoutAnyDetail() {
        let error = EnphaseClientError.rateLimited(period: nil, periodEnd: nil, detail: nil)
        #expect(error.errorDescription != nil)
        #expect(error.errorDescription?.contains("Minuten") == false)
    }

    // MARK: - Cross-device reconciliation (Epic 0, F0.4)

    @Test func syncWithCloudIfAvailableIsANoOpWithoutAnICloudAccount() async {
        // This development/test environment has no iCloud account signed in
        // (FileManager.ubiquityIdentityToken == nil), so the guard clause must return
        // immediately without touching the local count — exercised directly here since the
        // CloudKit round-trip itself can't be driven from a unit test (no CKContainer
        // abstraction, same reasoning as EnergieApp's own account-status fallback, F0.1).
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let budget = EnphaseRequestBudget(userDefaults: defaults, now: { date(2026, 9, 30) })
        await budget.recordRequest()
        let before = await budget.usedThisMonth()

        await budget.syncWithCloudIfAvailable()

        #expect(await budget.usedThisMonth() == before)
    }
}
