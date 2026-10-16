//
//  ShellyWidget.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 16.10.26.
//
//  Read-only (F16.4 — schalten stays app-only, a stray Homescreen tap has no confirmation
//  dialog like `ShellyPlugCard`'s does). Small shows just the overview (same numbers as
//  `ShellyPlugsSummaryCard`); medium/large add a per-plug list, capped at 3/7 rows so a long
//  device list doesn't overflow the widget's fixed size — `+ n weitere` covers the rest.
//

import SwiftUI
import WidgetKit

struct ShellyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: ShellyWidgetProvider.Entry

    var body: some View {
        content
            .padding()
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemMedium:
            HStack(alignment: .top, spacing: 16) {
                overview
                Divider()
                plugList(maxCount: 3)
            }
        case .systemLarge:
            VStack(alignment: .leading, spacing: 12) {
                overview
                Divider()
                plugList(maxCount: 7)
            }
        default:
            overview
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Steckdosen", systemImage: "powerplug.fill")
                .font(.caption.bold())
                .foregroundStyle(.shellyAccent)

            if let snapshot = entry.snapshot {
                Text(ShellyPlugDisplay.formatPower(snapshot.totalPower))
                    .font(.title2.bold())
                Text("\(snapshot.onCount) von \(snapshot.deviceCount) an")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if snapshot.offlineCount > 0 {
                    Text("\(snapshot.offlineCount) offline")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func plugList(maxCount: Int) -> some View {
        if let snapshot = entry.snapshot, !snapshot.plugs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshot.plugs.prefix(maxCount), id: \.id) { plug in
                    plugRow(plug)
                }
                let remaining = snapshot.plugs.count - maxCount
                if remaining > 0 {
                    Text("+ \(remaining) weitere")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func plugRow(_ plug: ShellyWidgetSnapshot.Plug) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor(for: plug))
                .frame(width: 8, height: 8)
            Text(plug.name)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(plug.isOnline ? plug.formattedPower : "Offline")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: plug))
    }

    private func dotColor(for plug: ShellyWidgetSnapshot.Plug) -> Color {
        guard plug.isOnline else { return .secondary }
        return plug.output == true ? .green : .secondary
    }

    private func accessibilityLabel(for plug: ShellyWidgetSnapshot.Plug) -> String {
        var parts = [plug.name]
        if !plug.isOnline {
            parts.append("Offline")
        } else if let output = plug.output {
            parts.append(output ? "Eingeschaltet" : "Ausgeschaltet")
            parts.append(plug.formattedPower)
        }
        return parts.joined(separator: ", ")
    }

    private var statusMessage: String? {
        switch entry.state {
        case .ready:
            return nil
        case .notConfigured:
            return "Bitte in der App einrichten"
        case .noDevices:
            return "Keine Steckdosen hinzugefügt"
        case .authFailed:
            return "Schlüssel abgelehnt — App öffnen"
        case .error:
            return entry.snapshot == nil ? "Keine Verbindung" : "Zuletzt aktualisiert"
        }
    }
}

struct ShellyWidget: Widget {
    let kind: String = "ShellyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ShellyWidgetProvider()) { entry in
            ShellyWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Steckdosen")
        .description("Gesamtleistung, Schaltzustand und die einzelnen Shelly-Steckdosen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private let previewPlugs: [ShellyWidgetSnapshot.Plug] = [
    ShellyWidgetSnapshot.Plug(id: "a", name: "Wohnzimmer", isOnline: true, output: true, formattedPower: "98 W"),
    ShellyWidgetSnapshot.Plug(id: "b", name: "Büro", isOnline: true, output: true, formattedPower: "44 W"),
    ShellyWidgetSnapshot.Plug(id: "c", name: "Garage", isOnline: false, output: nil, formattedPower: "–"),
    ShellyWidgetSnapshot.Plug(id: "d", name: "Keller", isOnline: true, output: false, formattedPower: "0 W"),
]

#Preview("Klein", as: .systemSmall) {
    ShellyWidget()
} timeline: {
    ShellyWidgetEntry(
        date: .now,
        snapshot: ShellyWidgetSnapshot(totalPower: 142, onCount: 2, deviceCount: 4, offlineCount: 1, plugs: previewPlugs, fetchedAt: .now),
        state: .ready
    )
}

#Preview("Mittel", as: .systemMedium) {
    ShellyWidget()
} timeline: {
    ShellyWidgetEntry(
        date: .now,
        snapshot: ShellyWidgetSnapshot(totalPower: 142, onCount: 2, deviceCount: 4, offlineCount: 1, plugs: previewPlugs, fetchedAt: .now),
        state: .ready
    )
}

#Preview("Groß", as: .systemLarge) {
    ShellyWidget()
} timeline: {
    ShellyWidgetEntry(
        date: .now,
        snapshot: ShellyWidgetSnapshot(totalPower: 142, onCount: 2, deviceCount: 4, offlineCount: 1, plugs: previewPlugs, fetchedAt: .now),
        state: .ready
    )
    ShellyWidgetEntry(date: .now, snapshot: nil, state: .notConfigured)
    ShellyWidgetEntry(date: .now, snapshot: nil, state: .noDevices)
    ShellyWidgetEntry(date: .now, snapshot: nil, state: .authFailed)
}
