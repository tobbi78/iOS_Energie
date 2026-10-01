//
//  EnergieWidget.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 01.10.26.
//

import SwiftUI
import WidgetKit

struct EnergieWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: PVWidgetProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("PV-Anlage", systemImage: "sun.max.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)

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
                metricBlock(value: formattedKWh(snapshot.producedWh), label: "Produktion")
                if let rate = snapshot.selfSufficiencyRate {
                    metricBlock(
                        value: rate.formatted(.percent.precision(.fractionLength(0))),
                        label: "Autarkiegrad",
                        tint: .green
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

    private func formattedKWh(_ wh: Double) -> String {
        (wh / 1000).formatted(.number.precision(.fractionLength(1))) + " kWh"
    }

    private var statusMessage: String? {
        switch entry.state {
        case .ready:
            return nil
        case .notSignedIn:
            return "Bitte in der App anmelden"
        case .tokenExpired:
            return "Sitzung abgelaufen — App öffnen"
        case .budgetExhausted:
            return "Monatslimit erreicht"
        case .error:
            return entry.snapshot == nil ? "Keine Verbindung" : "Zuletzt aktualisiert"
        }
    }
}

struct EnergieWidget: Widget {
    let kind: String = "EnergieWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PVWidgetProvider()) { entry in
            EnergieWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PV-Anlage")
        .description("Produktion und Autarkiegrad von heute.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    EnergieWidget()
} timeline: {
    PVWidgetEntry(
        date: .now,
        snapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, batterySocPercent: 54, fetchedAt: .now),
        state: .ready
    )
    PVWidgetEntry(date: .now, snapshot: nil, state: .notSignedIn)
}
