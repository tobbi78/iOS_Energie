//
//  DetailSectionComponents.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import SwiftUI

/// Shared visual building blocks for detail screens (Heizkreise/Warmwasser/Effizienz/...) — a
/// titled card and a label/value row. Ported from the macOS sibling project's
/// `DetailSectionComponents.swift`.
struct DetailCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A titled number tile, for stat rows that don't need the full `MetricCard` (icon/tint/subtitle).
struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.monospacedDigit())
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

/// Formats a value already known to be present as "<number> <unit>", or "–" if nil — the layout
/// every detail section uses for measured values.
func formattedMeasurement(_ value: Double?, unit: String, fractionDigits: ClosedRange<Int> = 0...1) -> String {
    guard let value else { return "–" }
    let number = value.formatted(.number.precision(.fractionLength(fractionDigits)))
    return unit.isEmpty ? number : number + " " + unit
}
