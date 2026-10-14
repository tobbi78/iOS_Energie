//
//  ShellyPlugsSummaryTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

@Suite
struct ShellyPlugsSummaryTests {
    private func device(_ id: String, name: String = "Steckdose") -> ShellyDevice {
        ShellyDevice(id: id, name: name, model: "Plug S")
    }

    private func onlineStatus(id: String, output: Bool?, apower: Double?) -> ShellyDeviceStatusDTO {
        ShellyDeviceStatusDTO(
            id: id, type: "SNPL-00112EU", code: nil, gen: "G2", online: true,
            status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: output, apower: apower, voltage: nil, current: nil, aenergy: nil))
        )
    }

    private func offlineStatus(id: String) -> ShellyDeviceStatusDTO {
        ShellyDeviceStatusDTO(id: id, type: nil, code: nil, gen: "G2", online: false, status: nil)
    }

    @Test func emptyDeviceListSummarizesToAllZerosAndNoPower() {
        let summary = ShellyPlugsSummary(devices: [], statuses: [:])
        #expect(summary.deviceCount == 0)
        #expect(summary.onCount == 0)
        #expect(summary.offlineCount == 0)
        #expect(summary.totalPower == nil)
    }

    @Test func countsMixedOnOffAndOfflineDevices() {
        let devices = [device("a"), device("b"), device("c")]
        let statuses = [
            "a": onlineStatus(id: "a", output: true, apower: 100),
            "b": onlineStatus(id: "b", output: false, apower: 0),
            "c": offlineStatus(id: "c"),
        ]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses)

        #expect(summary.deviceCount == 3)
        #expect(summary.onCount == 1)
        #expect(summary.offlineCount == 1)
        #expect(summary.totalPower == 100)
    }

    @Test func aDeviceWithNoStatusYetCountsAsOffline() {
        let devices = [device("a")]

        let summary = ShellyPlugsSummary(devices: devices, statuses: [:])

        #expect(summary.offlineCount == 1)
        #expect(summary.onCount == 0)
        #expect(summary.totalPower == nil)
    }

    @Test func totalPowerIsNilWhenAllDevicesAreOffline() {
        let devices = [device("a"), device("b")]
        let statuses = ["a": offlineStatus(id: "a"), "b": offlineStatus(id: "b")]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses)

        #expect(summary.totalPower == nil)
    }

    @Test func totalPowerSumsOnlyKnownReadingsAmongOnlineDevices() {
        let devices = [device("a"), device("b")]
        let statuses = [
            "a": onlineStatus(id: "a", output: true, apower: 42),
            // Online, but apower not (yet) known — e.g. a Gen1 device or unrecognized shape.
            "b": ShellyDeviceStatusDTO(id: "b", type: nil, code: nil, gen: "G1", online: true, status: nil),
        ]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses)

        #expect(summary.totalPower == 42)
    }

    @Test func ignoresStatusEntriesForDeviceIDsNotInTheSavedList() {
        let devices = [device("a")]
        let statuses = [
            "a": onlineStatus(id: "a", output: true, apower: 10),
            "unknown-id": onlineStatus(id: "unknown-id", output: true, apower: 1000),
        ]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses)

        #expect(summary.deviceCount == 1)
        #expect(summary.onCount == 1)
        #expect(summary.totalPower == 10)
    }

    @Test func aGen1OrUnrecognizedShapeOnlineDeviceCountsAsOnlineButNotOn() {
        let devices = [device("a")]
        let statuses = ["a": ShellyDeviceStatusDTO(id: "a", type: nil, code: nil, gen: "G1", online: true, status: nil)]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses)

        #expect(summary.offlineCount == 0)
        #expect(summary.onCount == 0)
        #expect(summary.totalPower == nil)
    }

    // MARK: - `totalEnergyToday` (F12.3)

    @Test func totalEnergyTodayIsNilWithoutAnyKnownReadings() {
        let devices = [device("a"), device("b")]

        let summary = ShellyPlugsSummary(devices: devices, statuses: [:])

        #expect(summary.totalEnergyToday == nil)
    }

    @Test func totalEnergyTodaySumsAcrossAllSavedDevices() {
        let devices = [device("a"), device("b"), device("c")]
        let statuses = [
            "a": onlineStatus(id: "a", output: true, apower: 100),
            "b": onlineStatus(id: "b", output: false, apower: 0),
            "c": offlineStatus(id: "c"),
        ]
        let energyToday = ["a": 400.0, "b": 50.0, "c": 20.0]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses, energyToday: energyToday)

        #expect(summary.totalEnergyToday == 470)
    }

    /// Unlike `totalPower`, an offline device's last known "today" figure still counts — it was
    /// genuinely consumed today even if the device can't be reached right now.
    @Test func totalEnergyTodayIncludesOfflineDevices() {
        let devices = [device("a")]
        let statuses = ["a": offlineStatus(id: "a")]
        let energyToday = ["a": 123.0]

        let summary = ShellyPlugsSummary(devices: devices, statuses: statuses, energyToday: energyToday)

        #expect(summary.totalEnergyToday == 123)
    }

    @Test func totalEnergyTodayIgnoresEntriesForDeviceIDsNotInTheSavedList() {
        let devices = [device("a")]
        let energyToday = ["a": 50.0, "unknown-id": 999.0]

        let summary = ShellyPlugsSummary(devices: devices, statuses: [:], energyToday: energyToday)

        #expect(summary.totalEnergyToday == 50)
    }

    @Test func totalEnergyTodayOnlySumsDevicesWithAKnownReading() {
        let devices = [device("a"), device("b")]
        let energyToday = ["a": 50.0]

        let summary = ShellyPlugsSummary(devices: devices, statuses: [:], energyToday: energyToday)

        #expect(summary.totalEnergyToday == 50)
    }
}
