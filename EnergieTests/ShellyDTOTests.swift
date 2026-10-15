//
//  ShellyDTOTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 15.10.26.
//

import Foundation
import Testing
@testable import Energie

/// Direct `JSONDecoder` tests for the tolerant decoding in `ShellyDTO.swift` (F18.1) — no
/// networking, unlike `ShellyClientTests`, which exercises the same decoders end-to-end through
/// `MockURLProtocol`.
@Suite
struct ShellyDTOTests {

    // MARK: - ShellyDeviceListResponse (/interface/device/list)

    @Test func deviceListResponseDecodesAnArrayOfDevices() throws {
        let json = #"{"data":{"devices":[{"id":"a1b2c3","name":"Wohnzimmer","type":"PlugS"}]}}"#
        let response = try JSONDecoder().decode(ShellyDeviceListResponse.self, from: Data(json.utf8))
        #expect(response.devices == [ShellyDiscoveredDevice(id: "a1b2c3", name: "Wohnzimmer", type: "PlugS")])
    }

    @Test func deviceListResponseDecodesADeviceDictionaryKeyedByID() throws {
        let json = #"{"data":{"devices":{"a1b2c3":{"name":"Büro","type":"PlugS"}}}}"#
        let response = try JSONDecoder().decode(ShellyDeviceListResponse.self, from: Data(json.utf8))
        #expect(response.devices == [ShellyDiscoveredDevice(id: "a1b2c3", name: "Büro", type: "PlugS")])
    }

    @Test func deviceListResponseIsEmptyWhenDevicesFieldIsMissing() throws {
        let json = #"{"data":{}}"#
        let response = try JSONDecoder().decode(ShellyDeviceListResponse.self, from: Data(json.utf8))
        #expect(response.devices.isEmpty)
    }

    @Test func deviceListResponseThrowsWhenDataFieldIsMissing() {
        let json = #"{"isok":true}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ShellyDeviceListResponse.self, from: Data(json.utf8))
        }
    }

    // MARK: - ShellyDeviceStatusDTO — gen/online tolerant decoding

    @Test func deviceStatusDTODecodesGenAsAString() throws {
        let json = #"{"id":"a1b2c3","gen":"G2","online":true}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.gen == "G2")
    }

    @Test func deviceStatusDTODecodesGenAsANumberNormalizedToAString() throws {
        let json = #"{"id":"a1b2c3","gen":2,"online":true}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.gen == "2")
    }

    @Test func deviceStatusDTOGenIsNilWhenMissing() throws {
        let json = #"{"id":"a1b2c3","online":true}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.gen == nil)
    }

    @Test func deviceStatusDTODecodesOnlineAsABool() throws {
        let json = #"{"id":"a1b2c3","online":true}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.online == true)
    }

    @Test func deviceStatusDTODecodesOnlineAsOneOrZero() throws {
        let onJSON = #"{"id":"a1b2c3","online":1}"#
        let offJSON = #"{"id":"a1b2c3","online":0}"#
        #expect(try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(onJSON.utf8)).online == true)
        #expect(try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(offJSON.utf8)).online == false)
    }

    @Test func deviceStatusDTOOnlineIsNilWhenMissing() throws {
        let json = #"{"id":"a1b2c3"}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.online == nil)
    }

    // MARK: - ShellyDeviceStatusDTO — switch:0 status

    @Test func deviceStatusDTODecodesTheSwitch0Status() throws {
        let json = #"{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true,"apower":42.5,"voltage":231.2,"current":0.18}}}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.status?.switch0 == ShellySwitchStatus(output: true, apower: 42.5, voltage: 231.2, current: 0.18))
    }

    @Test func deviceStatusDTOStatusIsNilWhenTheFieldIsAbsent() throws {
        let json = #"{"id":"a1b2c3","online":true}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.status == nil)
    }

    @Test func deviceStatusDTOSwitch0IsNilForAGen1StatusShape() throws {
        let json = #"{"id":"a1b2c3","online":true,"status":{"relays":[{"ison":true}]}}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.status?.switch0 == nil)
    }

    @Test func switchStatusFieldsAreIndividuallyOptional() throws {
        let json = #"{"id":"a1b2c3","online":true,"status":{"switch:0":{"output":true}}}"#
        let dto = try JSONDecoder().decode(ShellyDeviceStatusDTO.self, from: Data(json.utf8))
        #expect(dto.status?.switch0?.output == true)
        #expect(dto.status?.switch0?.apower == nil)
        #expect(dto.status?.switch0?.voltage == nil)
        #expect(dto.status?.switch0?.current == nil)
    }

    // MARK: - ShellyDeviceStatusResponse (/v2/devices/api/get) — envelope shapes

    @Test func deviceStatusResponseDecodesABareArray() throws {
        let json = #"[{"id":"a1b2c3","online":true}]"#
        let response = try JSONDecoder().decode(ShellyDeviceStatusResponse.self, from: Data(json.utf8))
        #expect(response.devices.map(\.id) == ["a1b2c3"])
    }

    @Test func deviceStatusResponseDecodesADataResultEnvelope() throws {
        let json = #"{"data":{"result":[{"id":"a1b2c3","online":true}]}}"#
        let response = try JSONDecoder().decode(ShellyDeviceStatusResponse.self, from: Data(json.utf8))
        #expect(response.devices.map(\.id) == ["a1b2c3"])
    }

    @Test func deviceStatusResponseDecodesADataArrayEnvelope() throws {
        let json = #"{"data":[{"id":"a1b2c3","online":true}]}"#
        let response = try JSONDecoder().decode(ShellyDeviceStatusResponse.self, from: Data(json.utf8))
        #expect(response.devices.map(\.id) == ["a1b2c3"])
    }

    @Test func deviceStatusResponseThrowsForAnUnrecognizedShape() {
        let json = #"{"message":"nope"}"#
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(ShellyDeviceStatusResponse.self, from: Data(json.utf8))
        }
    }
}
