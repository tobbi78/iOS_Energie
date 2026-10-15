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

    // MARK: - move (F17.2)

    @Test func moveReordersTowardTheFront() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Erste", model: nil))
        list.add(ShellyDevice(id: "bbb", name: "Zweite", model: nil))
        list.add(ShellyDevice(id: "ccc", name: "Dritte", model: nil))

        list.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        #expect(list.devices.map(\.id) == ["ccc", "aaa", "bbb"])
    }

    @Test func moveReordersTowardTheBack() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Erste", model: nil))
        list.add(ShellyDevice(id: "bbb", name: "Zweite", model: nil))
        list.add(ShellyDevice(id: "ccc", name: "Dritte", model: nil))

        // SwiftUI's `onMove` destination convention: moving "aaa" to the end is expressed as
        // `toOffset: 3` (one past the last index), not `2`.
        list.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        #expect(list.devices.map(\.id) == ["bbb", "ccc", "aaa"])
    }

    @Test func movePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let list = ShellyDeviceList(userDefaults: defaults)
        list.add(ShellyDevice(id: "aaa", name: "Erste", model: nil))
        list.add(ShellyDevice(id: "bbb", name: "Zweite", model: nil))

        list.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let reloaded = ShellyDeviceList(userDefaults: defaults)
        #expect(reloaded.devices.map(\.id) == ["bbb", "aaa"])
    }

    // MARK: - rename (F17.2)

    @Test func renameUpdatesTheMatchingDevice() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Alter Name", model: "Plug S"))

        let renamed = list.rename(id: "aaa", to: "Neuer Name")

        #expect(renamed)
        #expect(list.devices.first?.name == "Neuer Name")
        #expect(list.devices.first?.model == "Plug S")
    }

    @Test func renameTrimsWhitespace() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Alter Name", model: nil))

        #expect(list.rename(id: "aaa", to: "  Neuer Name  "))

        #expect(list.devices.first?.name == "Neuer Name")
    }

    @Test func renameRejectsAnEmptyName() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Alter Name", model: nil))

        let renamed = list.rename(id: "aaa", to: "   ")

        #expect(!renamed)
        #expect(list.devices.first?.name == "Alter Name")
    }

    @Test func renameRejectsAnUnknownID() {
        let list = makeList()
        list.add(ShellyDevice(id: "aaa", name: "Alter Name", model: nil))

        let renamed = list.rename(id: "zzz", to: "Neuer Name")

        #expect(!renamed)
        #expect(list.devices.first?.name == "Alter Name")
    }

    @Test func renamePersistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let list = ShellyDeviceList(userDefaults: defaults)
        list.add(ShellyDevice(id: "aaa", name: "Alter Name", model: nil))

        list.rename(id: "aaa", to: "Neuer Name")

        let reloaded = ShellyDeviceList(userDefaults: defaults)
        #expect(reloaded.devices.first?.name == "Neuer Name")
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
