//
//  CombinedWidget.swift
//  EnergieWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  One tile for users who'd rather place a single widget than the separate PV-Anlage and
//  Wärmepumpe ones. Needs more room than .systemSmall to show both sources legibly, so it only
//  offers .systemMedium/.systemLarge — the two individual widgets remain available for anyone
//  who wants .systemSmall or only cares about one source.
//

import SwiftUI
import WidgetKit

struct CombinedWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: CombinedWidgetProvider.Entry

    var body: some View {
        Group {
            if family == .systemLarge {
                VStack(alignment: .leading, spacing: 16) {
                    pvSection
                    Divider()
                    heatPumpSection
                }
            } else {
                HStack(alignment: .top, spacing: 16) {
                    pvSection
                    Divider()
                    heatPumpSection
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var pvSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("PV-Anlage", systemImage: "sun.max.fill")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            if let snapshot = entry.pvSnapshot {
                let layout: AnyLayout = family == .systemLarge
                    ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                layout {
                    metricBlock(
                        value: formattedKWh(snapshot.producedWh),
                        label: "Produktion",
                        tint: .orange
                    )
                    if let rate = snapshot.selfSufficiencyRate {
                        metricBlock(
                            value: rate.formatted(.percent.precision(.fractionLength(0))),
                            label: "Autarkiegrad",
                            tint: .green
                        )
                    }
                }
            }

            if let statusMessage = pvStatusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var heatPumpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Wärmepumpe", systemImage: "heater.vertical.fill")
                .font(.caption.bold())
                .foregroundStyle(.red)

            if let snapshot = entry.heatPumpSnapshot {
                let layout: AnyLayout = family == .systemLarge
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

            if let statusMessage = heatPumpStatusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricBlock(value: String, label: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title3.bold())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedKWh(_ wh: Double) -> String {
        (wh / 1000).formatted(.number.precision(.fractionLength(1))) + " kWh"
    }

    private var pvStatusMessage: String? {
        switch entry.pvState {
        case .ready: return nil
        case .notSignedIn: return "Bitte anmelden"
        case .tokenExpired: return "Sitzung abgelaufen"
        case .budgetExhausted: return "Monatslimit erreicht"
        case .error: return entry.pvSnapshot == nil ? "Keine Verbindung" : "Zuletzt aktualisiert"
        }
    }

    private var heatPumpStatusMessage: String? {
        switch entry.heatPumpState {
        case .ready: return nil
        case .notSignedIn: return "Bitte anmelden"
        case .deviceNotResolved: return "Gerät wird ermittelt"
        case .error: return entry.heatPumpSnapshot == nil ? "Keine Verbindung" : "Zuletzt aktualisiert"
        }
    }
}

struct CombinedWidget: Widget {
    let kind: String = "CombinedWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CombinedWidgetProvider()) { entry in
            CombinedWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("PV & Wärmepumpe")
        .description("Produktion, Autarkiegrad, Anlagendruck und Außentemperatur in einer Kachel.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview(as: .systemMedium) {
    CombinedWidget()
} timeline: {
    CombinedWidgetEntry(
        date: .now,
        pvSnapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, batterySocPercent: 54, fetchedAt: .now),
        pvState: .ready,
        heatPumpSnapshot: HPWidgetDataSource.Snapshot(pressureBar: 1.4, outsideTemperatureCelsius: 8.0, fetchedAt: .now),
        heatPumpState: .ready
    )
    CombinedWidgetEntry(date: .now, pvSnapshot: nil, pvState: .notSignedIn, heatPumpSnapshot: nil, heatPumpState: .notSignedIn)
}
