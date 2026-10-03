//
//  ViessmannFeatureLookup.swift
//  Energie
//
//  Created by Tobias Florian on 03.10.26.
//

import Foundation

/// Small lookup helpers for reading specific values out of a features poll by exact
/// feature/property name — shared by the overview (HP-3) and detail screens (HP-4). Ported from
/// the macOS sibling project's `FeatureValueLookup.swift`.
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

    /// Reads a comma-separated list of instance indices from a feature like `heating.circuits`'s
    /// `enabled` property (e.g. "0,1") — the authoritative source for "how many circuits/
    /// compressors/etc. does this device actually have" (HP-4), rather than guessing from which
    /// indexed feature keys happen to appear.
    func enabledIndices(_ featureName: String) -> [Int] {
        guard let raw = stringValue(featureName, "enabled") else { return [] }
        return raw.split(separator: ",").compactMap { Int($0) }.sorted()
    }
}
