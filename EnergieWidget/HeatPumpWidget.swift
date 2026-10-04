//
//  HeatPumpWidget.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//

import SwiftUI
import WidgetKit

struct HeatPumpWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: HPWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wärmepumpe", systemImage: "heater.vertical.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)

            metrics

            Spacer(minLength: 0)

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var metrics: some View {
        if let snapshot = entry.snapshot {
            let layout: AnyLayout = family == .systemMedium
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            layout {
                if let pressureBar = snapshot.pressureBar {
                    metricBlock(
                        value: pressureBar.formatted(.number.precision(.fractionLength(1...2))) + " bar",
                        label: "Anlagendruck",
                        tint: .red
                    )
                }
                if let outsideTemperature = snapshot.outsideTemperatureCelsius {
                    metricBlock(
                        value: outsideTemperature.formatted(.number.precision(.fractionLength(1))) + " °C",
                        label: "Außentemperatur",
                        tint: .blue
                    )
                }
            }
        }
    }

    private func metricBlock(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var statusMessage: String? {
        switch entry.state {
        case .ready:
            return nil
        case .notSignedIn:
            return "Bitte in der App anmelden"
        case .deviceNotResolved:
            return "Gerät wird ermittelt — App öffnen"
        case .error:
            return entry.snapshot == nil ? "Keine Verbindung" : "Zuletzt aktualisiert"
        }
    }
}

struct HeatPumpWidget: Widget {
    let kind: String = "HeatPumpWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HPWidgetProvider()) { entry in
            HeatPumpWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Wärmepumpe")
        .description("Anlagendruck und Außentemperatur, mit Hintergrund-Druckalarm.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    HeatPumpWidget()
} timeline: {
    HPWidgetEntry(
        date: .now,
        snapshot: HPWidgetDataSource.Snapshot(pressureBar: 1.4, outsideTemperatureCelsius: 8.0, fetchedAt: .now),
        state: .ready
    )
    HPWidgetEntry(date: .now, snapshot: nil, state: .notSignedIn)
}
