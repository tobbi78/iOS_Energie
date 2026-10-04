//
//  HeatPumpPressureAlertTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//
//  Ported from the macOS sibling project's PressureAlertTests.swift
//  (https://github.com/tobbi78/Dashboard_Waermepumpe) — same pure logic, renamed types, no
//  "recipient" concept (local notification instead of iMessage).

import Foundation
import Testing
@testable import Energie

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct HeatPumpPressureAlertTrackerTests {
    private let threshold = 1.0
    private let repeatInterval: TimeInterval = 4 * 3600

    @Test func nilPressureNeverAlertsAndLeavesStateUnchanged() {
        let state = HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: date(2026, 9, 25, 10, 0))
        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: nil, threshold: threshold, now: date(2026, 9, 25, 12, 0),
            state: state, recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == nil)
        #expect(newState == state)
    }

    @Test func stayingAboveThresholdNeverAlerts() {
        let (alert, state) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 1.7, threshold: threshold, now: date(2026, 9, 25, 12, 0),
            state: HeatPumpPressureAlertTracker.State(), recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == nil)
        #expect(state == HeatPumpPressureAlertTracker.State())
    }

    @Test func exactlyAtThresholdDoesNotCountAsBelow() {
        // "< threshold" per spec — exactly at the threshold is still fine.
        let (alert, state) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 1.0, threshold: threshold, now: date(2026, 9, 25, 12, 0),
            state: HeatPumpPressureAlertTracker.State(), recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == nil)
        #expect(!state.isBelowThreshold)
    }

    @Test func crossingBelowThresholdAlwaysNotifies() {
        let now = date(2026, 9, 25, 10, 0)
        let (alert, state) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 0.8, threshold: threshold, now: now,
            state: HeatPumpPressureAlertTracker.State(), recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == .drop)
        #expect(state == HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: now))
    }

    @Test func stayingBelowWithoutRepeatIntervalElapsedDoesNotNotifyAgain() {
        let lastNotified = date(2026, 9, 25, 10, 0)
        let now = lastNotified.addingTimeInterval(3600)
        let state = HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: lastNotified)

        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 0.8, threshold: threshold, now: now,
            state: state, recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == nil)
        #expect(newState == state)
    }

    @Test func stayingBelowWithRepeatIntervalElapsedSendsReminder() {
        let lastNotified = date(2026, 9, 25, 10, 0)
        let now = lastNotified.addingTimeInterval(repeatInterval)
        let state = HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: lastNotified)

        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 0.8, threshold: threshold, now: now,
            state: state, recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == .repeatReminder)
        #expect(newState == HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: now))
    }

    @Test func recoveryAboveThresholdAlertsWhenEnabled() {
        let state = HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: date(2026, 9, 25, 10, 0))

        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 1.5, threshold: threshold, now: date(2026, 9, 25, 12, 0),
            state: state, recoveryEnabled: true, repeatInterval: repeatInterval
        )
        #expect(alert == .recovery)
        #expect(newState == HeatPumpPressureAlertTracker.State())
    }

    @Test func recoveryDoesNotAlertWhenDisabledButStateStillResets() {
        let state = HeatPumpPressureAlertTracker.State(isBelowThreshold: true, lastNotifiedAt: date(2026, 9, 25, 10, 0))

        let (alert, newState) = HeatPumpPressureAlertTracker.evaluate(
            currentPressure: 1.5, threshold: threshold, now: date(2026, 9, 25, 12, 0),
            state: state, recoveryEnabled: false, repeatInterval: repeatInterval
        )
        #expect(alert == nil)
        #expect(newState == HeatPumpPressureAlertTracker.State())
    }
}

@MainActor
struct HeatPumpPressureAlertSettingsTests {
    @Test func defaultsMatchSpec() {
        let settings = HeatPumpPressureAlertSettings(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(settings.threshold == 1.0)
        #expect(settings.isEnabled == true)
        #expect(settings.recoveryMessageEnabled == true)
        #expect(settings.repeatInterval == 4 * 3600)
    }

    @Test func settersPersistAndReloadFromTheSameDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = HeatPumpPressureAlertSettings(defaults: defaults)
        settings.setThreshold(0.8)
        settings.setEnabled(false)
        settings.setRecoveryMessageEnabled(false)
        settings.setRepeatInterval(3600)

        let reloaded = HeatPumpPressureAlertSettings(defaults: defaults)
        #expect(reloaded.threshold == 0.8)
        #expect(reloaded.isEnabled == false)
        #expect(reloaded.recoveryMessageEnabled == false)
        #expect(reloaded.repeatInterval == 3600)
    }
}
