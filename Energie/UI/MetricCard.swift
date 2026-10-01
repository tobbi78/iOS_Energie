//
//  MetricCard.swift
//  Energie
//
//  Created by Tobias Florian on 01.10.26.
//

import SwiftUI

/// Source-agnostic KPI tile, shared between PV and heat-pump screens (and the combined Home
/// screen) instead of duplicating it per source (see Plans/Waermepumpe-Integration.md, Abschnitt 6).
struct MetricCard: View {
    let title: String
    var value: String
    var subtitle: String?
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.bold())
                .contentTransition(.numericText())
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            // Always reserve one caption line, even without a subtitle, so every card in a grid
            // has the same height.
            Text(subtitle ?? " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .opacity(subtitle == nil ? 0 : 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
