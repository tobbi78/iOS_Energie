//
//  ViessmannFeatureLookup.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Byte-identical duplicate of Energie/Viessmann/ViessmannFeatureLookup.swift (see
//  ViessmannEndpoints.swift for why). Keep both copies in sync by hand.

import Foundation

extension Array where Element == ViessmannFeatureDTO {
    func feature(_ featureName: String) -> ViessmannFeatureDTO? {
        first(where: { $0.feature == featureName })
    }

    func property(_ featureName: String, _ property: String = "value") -> ViessmannFeaturePropertyDTO? {
        feature(featureName)?.properties[property]
    }

    func numericValue(_ featureName: String, _ property: String = "value") -> Double? {
        self.property(featureName, property)?.value.numericValue
    }

    func stringValue(_ featureName: String, _ property: String) -> String? {
        self.property(featureName, property)?.value.stringRepresentation
    }

    func enabledIndices(_ featureName: String) -> [Int] {
        guard let raw = stringValue(featureName, "enabled") else { return [] }
        return raw.split(separator: ",").compactMap { Int($0) }.sorted()
    }
}
