//
//  EnergieTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 30.09.26.
//

import Foundation
import Testing
@testable import Energie

struct EnergieTests {

    @Test func decodesSystemsResponse() throws {
        let json = """
        { "systems": [{ "system_id": 698910067 }] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseSystemsResponse.self, from: json)
        #expect(decoded.systems.first?.systemID == 698910067)
    }

    @Test func decodesSystemSummary() throws {
        let json = """
        { "energy_today": 12345, "current_power": 500 }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseSystemSummaryDTO.self, from: json)
        #expect(decoded.energyTodayWh == 12345)
        #expect(decoded.currentPowerW == 500)
    }

    @Test func sumsMeterTelemetryIntervals() throws {
        let json = """
        { "intervals": [{ "end_at": 1, "enwh": 40 }, { "end_at": 2, "enwh": 60 }] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseMeterTelemetryResponse.self, from: json)
        #expect(decoded.totalWh == 100)
    }

    @Test func sumsNestedEnergyFlowIntervals() throws {
        let json = """
        { "intervals": [[{ "end_at": 1, "wh_imported": 10 }, { "end_at": 2, "wh_imported": 20 }]] }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseEnergyFlowTelemetryResponse.self, from: json)
        #expect(decoded.totalWh == 30)
    }

    @Test func decodesBatteryTelemetryAndUsesLatestSoc() throws {
        let json = """
        {
          "intervals": [
            { "end_at": 1, "charge": { "enwh": 40 }, "discharge": { "enwh": 0 }, "soc": { "percent": 25 } },
            { "end_at": 2, "charge": { "enwh": 10 }, "discharge": { "enwh": 5 }, "soc": { "percent": 30 } }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(EnphaseBatteryTelemetryResponse.self, from: json)
        #expect(decoded.totalChargedWh == 50)
        #expect(decoded.totalDischargedWh == 5)
        #expect(decoded.latestSocPercent == 30)
    }

    @Test func selfSufficiencyRateIsNilWithoutConsumption() {
        let sample = PVDailySample(date: .now, consumedWh: 0, importedWh: 0)
        #expect(sample.selfSufficiencyRate == nil)
    }

    @Test func selfSufficiencyRateComputation() {
        let sample = PVDailySample(date: .now, consumedWh: 100, importedWh: 40)
        #expect(sample.selfSufficiencyRate == 0.6)
    }

    @Test func estimatedFeedInRevenueComputation() {
        let sample = PVDailySample(date: .now, exportedWh: 2000)
        #expect(sample.estimatedFeedInRevenue(tariffPerKWh: 0.08) == 0.16)
    }
}
