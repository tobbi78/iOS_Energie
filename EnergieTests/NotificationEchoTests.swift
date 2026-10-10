//
//  NotificationEchoTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 11.10.26.
//

import Foundation
import Testing
@testable import Energie

/// Covers `NotificationEcho.evaluate`, the pure comparison behind the tab-icon bounce (F10.8).
/// The surrounding `refresh()` talks to the live `UNUserNotificationCenter`/`UserDefaults` and,
/// like `HeatPumpModel.notifyPressureAlert`, is deliberately left untested directly — only the
/// decision logic is.
@MainActor
struct NotificationEchoTests {
    @Test func noDeliveredNotificationsNeverTriggers() {
        let result = NotificationEcho.evaluate(deliveredDates: [], lastSeenDate: nil)
        #expect(result.isNew == false)
        #expect(result.newestDate == nil)
    }

    @Test func firstEverNotificationTriggersEvenWithoutALastSeenDate() {
        let date = Date()
        let result = NotificationEcho.evaluate(deliveredDates: [date], lastSeenDate: nil)
        #expect(result.isNew == true)
        #expect(result.newestDate == date)
    }

    @Test func aNotificationNewerThanLastSeenTriggers() {
        let lastSeen = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        let result = NotificationEcho.evaluate(deliveredDates: [newer], lastSeenDate: lastSeen)
        #expect(result.isNew == true)
        #expect(result.newestDate == newer)
    }

    @Test func aNotificationNoNewerThanLastSeenDoesNotTrigger() {
        let lastSeen = Date(timeIntervalSince1970: 2000)
        let result = NotificationEcho.evaluate(deliveredDates: [lastSeen], lastSeenDate: lastSeen)
        #expect(result.isNew == false)
        #expect(result.newestDate == lastSeen)
    }

    @Test func anOlderNotificationThanLastSeenDoesNotTrigger() {
        let lastSeen = Date(timeIntervalSince1970: 2000)
        let older = Date(timeIntervalSince1970: 1000)
        let result = NotificationEcho.evaluate(deliveredDates: [older], lastSeenDate: lastSeen)
        #expect(result.isNew == false)
        #expect(result.newestDate == older)
    }

    @Test func onlyTheNewestOfSeveralDeliveredNotificationsDecidesTheOutcome() {
        let lastSeen = Date(timeIntervalSince1970: 1500)
        let older = Date(timeIntervalSince1970: 1000)
        let newer = Date(timeIntervalSince1970: 2000)
        let result = NotificationEcho.evaluate(deliveredDates: [older, newer], lastSeenDate: lastSeen)
        #expect(result.isNew == true)
        #expect(result.newestDate == newer)
    }
}
