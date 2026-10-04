//
//  ViessmannFeatureLookupTests.swift
//  EnergieTests
//
//  Created by Tobias Florian on 04.10.26.
//

import Foundation
import Testing
@testable import Energie

private func feature(_ name: String, _ properties: [String: ViessmannFeatureValue]) -> ViessmannFeatureDTO {
    ViessmannFeatureDTO(
        feature: name,
        isEnabled: true,
        isReady: true,
        timestamp: nil,
        properties: properties.mapValues { ViessmannFeaturePropertyDTO(type: nil, value: $0, unit: nil) }
    )
}

struct ViessmannFeatureLookupTests {
    private let features = [
        feature("heating.circuits", ["enabled": .string("0,1")]),
        feature("heating.sensors.temperature.outside", ["value": .number(16.8), "status": .string("connected")]),
    ]

    @Test func featureFindsByExactName() {
        #expect(features.feature("heating.circuits") != nil)
        #expect(features.feature("unknown.feature") == nil)
    }

    @Test func propertyDefaultsToValueKey() {
        #expect(features.property("heating.sensors.temperature.outside")?.value.numericValue == 16.8)
    }

    @Test func numericValueReturnsNilForMissingFeatureOrProperty() {
        #expect(features.numericValue("unknown.feature") == nil)
        #expect(features.numericValue("heating.sensors.temperature.outside", "missingProperty") == nil)
    }

    @Test func stringValueReadsNamedProperty() {
        #expect(features.stringValue("heating.sensors.temperature.outside", "status") == "connected")
    }

    @Test func enabledIndicesParsesCommaSeparatedList() {
        #expect(features.enabledIndices("heating.circuits") == [0, 1])
    }

    @Test func enabledIndicesIsEmptyWhenFeatureMissing() {
        #expect(features.enabledIndices("heating.compressors") == [])
    }

    @Test func enabledIndicesSortsOutOfOrderIndices() {
        let unsorted = [feature("heating.compressors", ["enabled": .string("2,0,1")])]
        #expect(unsorted.enabledIndices("heating.compressors") == [0, 1, 2])
    }
}
