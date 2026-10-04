//
//  WatchSyncServiceTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
import WatchConnectivity
@testable import Energie

@MainActor
struct WatchSyncServiceTests {
    private func pvUpdate(producedTodayWh: Double = 4200, fetchedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> WatchSyncService.PVUpdate {
        WatchSyncService.PVUpdate(
            producedTodayWh: producedTodayWh,
            selfSufficiencyRate: 0.6,
            batterySocPercent: 50,
            fetchedAt: fetchedAt
        )
    }

    private func heatPumpUpdate(pressureBar: Double = 1.8, fetchedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)) -> WatchSyncService.HeatPumpUpdate {
        WatchSyncService.HeatPumpUpdate(
            pressureBar: pressureBar,
            outsideTemperatureCelsius: 6.5,
            pressureAlertActive: false,
            fetchedAt: fetchedAt
        )
    }

    private func decodedSnapshot(from context: [String: Any]) throws -> WatchSnapshot {
        let data = try #require(context["snapshot"] as? Data)
        return try JSONDecoder().decode(WatchSnapshot.self, from: data)
    }

    @Test func activatesTheSessionOnInit() {
        let session = FakeWatchConnectivitySession()
        _ = WatchSyncService(session: session)
        #expect(session.activateCallCount == 1)
    }

    @Test func sendsASnapshotWhenPairedAndInstalled() throws {
        let session = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate())

        #expect(session.sentContexts.count == 1)
        let snapshot = try decodedSnapshot(from: session.sentContexts[0])
        #expect(snapshot.pvProducedTodayWh == 4200)
        #expect(service.lastSentSnapshot == snapshot)
    }

    @Test func doesNotResendAnIdenticalUpdate() {
        let session = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate())
        service.updatePV(pvUpdate())

        #expect(session.sentContexts.count == 1)
    }

    @Test func resendsWhenTheValueActuallyChanges() {
        let session = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate(producedTodayWh: 4200))
        service.updatePV(pvUpdate(producedTodayWh: 4300))

        #expect(session.sentContexts.count == 2)
    }

    @Test func mergesPVAndHeatPumpUpdatesIntoOneSnapshot() throws {
        let session = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate())
        service.updateHeatPump(heatPumpUpdate())

        #expect(session.sentContexts.count == 2)
        let merged = try decodedSnapshot(from: session.sentContexts[1])
        #expect(merged.pvProducedTodayWh == 4200)
        #expect(merged.heatPumpPressureBar == 1.8)
    }

    @Test func doesNotSendWhenNotPaired() {
        let session = FakeWatchConnectivitySession(isPaired: false)
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate())

        #expect(session.sentContexts.isEmpty)
    }

    @Test func doesNotSendWhenWatchAppNotInstalled() {
        let session = FakeWatchConnectivitySession(isWatchAppInstalled: false)
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate())

        #expect(session.sentContexts.isEmpty)
    }

    @Test func doesNotSendWhenSessionIsNotActivated() {
        let session = FakeWatchConnectivitySession(activationState: .inactive)
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate())

        #expect(session.sentContexts.isEmpty)
    }

    @Test func retriesOnTheNextUpdateAfterAFailedSend() {
        let session = FakeWatchConnectivitySession()
        session.updateApplicationContextError = URLError(.notConnectedToInternet)
        let service = WatchSyncService(session: session)

        service.updatePV(pvUpdate(producedTodayWh: 4200))
        #expect(session.sentContexts.isEmpty)
        #expect(service.lastSentSnapshot == nil)

        session.updateApplicationContextError = nil
        service.updateHeatPump(heatPumpUpdate())

        #expect(session.sentContexts.count == 1)
    }
}
