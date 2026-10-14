//
//  ShellyDeviceListTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 14.10.26.
//

import Foundation
import Testing
@testable import Energie

@MainActor
struct ShellyDeviceListTests {
    private func makeList() -> ShellyDeviceList {
        ShellyDeviceList(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
    }

    @Test func startsEmpty() {
        #expect(makeList().devices.isEmpty)
    }

    @Test func addAppendsADevice() {
        let list = makeList()
        let added = list.add(ShellyDevice(id: "a1b2c3", name: "Wohnzimmer", model: "Plug S"))
        #expect(added)
        #expect(list.devices == [ShellyDevice(id: "a1b2c3", name: "Wohnzimmer", model: "Plug S")])
    }

    @Test func addRejectsADuplicateID() {
        let list = makeList()
        #expect(list.add(ShellyDevice(id: "a1b2c3", name: "Wohnzimmer", model: nil)))
        let addedAgain = list.add(ShellyDevice(id: "a1b2c3", name: "Zweiter Name", model: nil))
        #expect(!addedAgain)
        #expect(list.devices.count == 1)
        #expect(list.devices.first?.name == "Wohnzimmer")
    }

    @Test func removeAtOffsetsRemovesTheRightDevice() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Erste", model: nil))
        list.add(ShellyDevice(id: "bbb", name: "Zweite", model: nil))
        list.add(ShellyDevice(id: "ccc", name: "Dritte", model: nil))

        list.remove(atOffsets: IndexSet(integer: 1))

        #expect(list.devices.map(\.id) == ["aaa", "ccc"])
    }

    @Test func persistsAcrossInstancesWithTheSameUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let list = ShellyDeviceList(userDefaults: defaults)
        list.add(ShellyDevice(id: "a1b2c3", name: "Wohnzimmer", model: "Plug S"))

        let reloaded = ShellyDeviceList(userDefaults: defaults)
        #expect(reloaded.devices == [ShellyDevice(id: "a1b2c3", name: "Wohnzimmer", model: "Plug S")])
    }

    // MARK: - normalizedDeviceID

    @Test func normalizedDeviceIDTrimsAndLowercases() {
        #expect(ShellyDeviceList.normalizedDeviceID("  A1B2C3  ") == "a1b2c3")
    }

    @Test func normalizedDeviceIDRejectsEmptyInput() {
        #expect(ShellyDeviceList.normalizedDeviceID("   ") == nil)
    }

    @Test func normalizedDeviceIDRejectsDisallowedCharacters() {
        #expect(ShellyDeviceList.normalizedDeviceID("a1b2-c3") == nil)
        #expect(ShellyDeviceList.normalizedDeviceID("a1 b2c3") == nil)
        #expect(ShellyDeviceList.normalizedDeviceID("a1b2c3!") == nil)
    }
}
