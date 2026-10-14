//
//  ShellyPlugsSummaryCard.swift
//  Energie
//
//  Created by Tobias Florian on 14.10.26.
//

import SwiftUI

/// Overview card for F12.2: total power draw plus "x of y on"/offline counts across every saved
/// plug, shown once above the per-plug `ShellyPlugCard` list in `ShellyView` — only relevant
/// once there's more than one plug to lose track of.
///
/// Visual language borrowed from `ShellyPlugCard`/`MetricCard` (same background/corner radius,
/// same badge style) so it reads as part of the same "Steckdosen" tab rather than a one-off.
struct ShellyPlugsSummaryCard: View {
    let summary: ShellyPlugsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text(formattedTotalPower)
                .font(.title.bold())
                .contentTransition(.numericText())
            HStack(spacing: 8) {
                Text("\(summary.onCount) von \(summary.deviceCount) an")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if summary.offlineCount > 0 {
                    offlineBadge
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var header: some View {
        HStack {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title3)
                .foregroundStyle(.shellyAccent)
            Text("Übersicht")
                .font(.headline)
            Spacer()
        }
    }

    private var offlineBadge: some View {
        Text("\(summary.offlineCount) offline")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var formattedTotalPower: String {
        guard let totalPower = summary.totalPower else { return "–" }
        return totalPower.formatted(.number.precision(.fractionLength(0))) + " W"
    }

    private var accessibilitySummary: String {
        var parts = ["Übersicht", "Gesamtleistung \(formattedTotalPower)", "\(summary.onCount) von \(summary.deviceCount) an"]
        if summary.offlineCount > 0 {
            parts.append("\(summary.offlineCount) offline")
        }
        return parts.joined(separator: ", ")
    }
}

#Preview("Gemischt") {
    ShellyPlugsSummaryCard(summary: ShellyPlugsSummary(
        devices: [
            ShellyDevice(id: "a", name: "Wohnzimmer", model: "Plug S"),
            ShellyDevice(id: "b", name: "Büro", model: "Plug S"),
            ShellyDevice(id: "c", name: "Garage", model: "Plug S"),
        ],
        statuses: [
            "a": ShellyDeviceStatusDTO(id: "a", type: "SNPL-00112EU", code: nil, gen: "G2", online: true, status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: true, apower: 123, voltage: 231.4, current: 0.53))),
            "b": ShellyDeviceStatusDTO(id: "b", type: "SNPL-00112EU", code: nil, gen: "G2", online: true, status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: false, apower: 0, voltage: 230.9, current: 0))),
            "c": ShellyDeviceStatusDTO(id: "c", type: nil, code: nil, gen: "G2", online: false, status: nil),
        ]
    ))
    .padding()
}

#Preview("Alle aus") {
    ShellyPlugsSummaryCard(summary: ShellyPlugsSummary(
        devices: [
            ShellyDevice(id: "a", name: "Wohnzimmer", model: "Plug S"),
            ShellyDevice(id: "b", name: "Büro", model: "Plug S"),
        ],
        statuses: [
            "a": ShellyDeviceStatusDTO(id: "a", type: "SNPL-00112EU", code: nil, gen: "G2", online: true, status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: false, apower: 0, voltage: 230.9, current: 0))),
            "b": ShellyDeviceStatusDTO(id: "b", type: "SNPL-00112EU", code: nil, gen: "G2", online: true, status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: false, apower: 0, voltage: 230.9, current: 0))),
        ]
    ))
    .padding()
}

#Preview("Mit Offline-Geräten") {
    ShellyPlugsSummaryCard(summary: ShellyPlugsSummary(
        devices: [
            ShellyDevice(id: "a", name: "Wohnzimmer", model: "Plug S"),
            ShellyDevice(id: "b", name: "Büro", model: "Plug S"),
            ShellyDevice(id: "c", name: "Garage", model: "Plug S"),
        ],
        statuses: [
            "a": ShellyDeviceStatusDTO(id: "a", type: "SNPL-00112EU", code: nil, gen: "G2", online: true, status: ShellyDeviceStatus(switch0: ShellySwitchStatus(output: true, apower: 50, voltage: 231.4, current: 0.22))),
        ]
    ))
    .padding()
}
