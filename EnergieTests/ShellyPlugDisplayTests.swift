//
//  ShellyPlugDisplayTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import Testing
@testable import Energie

@Suite
struct ShellyPlugDisplayTests {
    private func status(online: Bool?, output: Bool?, apower: Double? = nil, voltage: Double? = nil, current: Double? = nil, hasSwitch0: Bool = true) -> ShellyDeviceStatusDTO {
        ShellyDeviceStatusDTO(
            id: "a1b2c3", type: "SNPL-00112EU", code: nil, gen: "G2", online: online,
            status: hasSwitch0 ? ShellyDeviceStatus(switch0: ShellySwitchStatus(output: output, apower: apower, voltage: voltage, current: current)) : nil
        )
    }

    // MARK: - isOnline / output / canToggle

    @Test func nilStatusIsOfflineAndNotToggleable() {
        let display = ShellyPlugDisplay(status: nil)
        #expect(!display.isOnline)
        #expect(display.output == nil)
        #expect(!display.canToggle)
    }

    @Test func offlineStatusIsNotToggleableEvenWithAKnownOutput() {
        let display = ShellyPlugDisplay(status: status(online: false, output: true))
        #expect(!display.isOnline)
        #expect(!display.canToggle)
    }

    @Test func onlineWithUnknownOutputIsNotToggleable() {
        let display = ShellyPlugDisplay(status: status(online: true, output: nil))
        #expect(display.isOnline)
        #expect(display.output == nil)
        #expect(!display.canToggle)
    }

    @Test func onlineWithAGen1StatusShapeIsNotToggleable() {
        let display = ShellyPlugDisplay(status: status(online: true, output: nil, hasSwitch0: false))
        #expect(display.isOnline)
        #expect(!display.canToggle)
    }

    @Test func onlineWithAKnownOutputIsToggleable() {
        let display = ShellyPlugDisplay(status: status(online: true, output: true))
        #expect(display.isOnline)
        #expect(display.output == true)
        #expect(display.canToggle)
    }

    // MARK: - formatted readings

    @Test func formattedReadingsAreADashWhenTheValueIsUnknown() {
        let display = ShellyPlugDisplay(status: status(online: true, output: true))
        #expect(display.formattedPower == "–")
        #expect(display.formattedVoltage == "–")
        #expect(display.formattedCurrent == "–")
    }

    @Test func formattedReadingsAreADashForANilStatus() {
        let display = ShellyPlugDisplay(status: nil)
        #expect(display.formattedPower == "–")
        #expect(display.formattedVoltage == "–")
        #expect(display.formattedCurrent == "–")
    }

    @Test func formattedPowerRoundsToNoDecimalPlaces() {
        let display = ShellyPlugDisplay(status: status(online: true, output: true, apower: 42.6))
        #expect(display.formattedPower == "43 W")
    }

    // Decimal separator follows the system locale (`.formatted(.number...)`, no explicit
    // `Locale` override anywhere in `ShellyPlugDisplay`) — the simulator/CI environment this
    // project runs in is German, hence the comma.
    @Test func formattedVoltageRoundsToOneDecimalPlace() {
        let display = ShellyPlugDisplay(status: status(online: true, output: true, voltage: 231.26))
        #expect(display.formattedVoltage == "231,3 V")
    }

    @Test func formattedCurrentRoundsToTwoDecimalPlaces() {
        let display = ShellyPlugDisplay(status: status(online: true, output: true, current: 0.184))
        #expect(display.formattedCurrent == "0,18 A")
    }

    // MARK: - static formatPower — shared with ShellyPlugsSummaryCard

    @Test func staticFormatPowerMatchesTheInstanceFormatting() {
        #expect(ShellyPlugDisplay.formatPower(123.4) == "123 W")
        #expect(ShellyPlugDisplay.formatPower(nil) == "–")
    }
}
