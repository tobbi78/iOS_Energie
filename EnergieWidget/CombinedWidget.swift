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
                    if showsShellySection {
                        Divider()
                        shellySection
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 16) {
                        pvSection
                        Divider()
                        heatPumpSection
                    }
                    if showsShellySection {
                        Divider()
                        shellyCompactRow
                    }
                }
            }
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Hidden entirely for a user without Shelly set up (F16.3, Nutzerentscheidung 2026-10-15) —
    /// only `.notConfigured`/`.noDevices` hide the section; an auth failure or fetch error still
    /// shows it (with its own status message), same as the PV/Wärmepumpe sections never
    /// disappear on error.
    private var showsShellySection: Bool {
        entry.shellyState != .notConfigured && entry.shellyState != .noDevices
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

    /// Large family only — full section matching `pvSection`/`heatPumpSection`'s shape, with its
    /// own "Gesamtleistung"/"An" metrics side by side (F16.3).
    @ViewBuilder
    private var shellySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Steckdosen", systemImage: "powerplug.fill")
                .font(.caption.bold())
                .foregroundStyle(.shellyAccent)

            if let snapshot = entry.shellySnapshot {
                HStack(alignment: .top, spacing: 24) {
                    metricBlock(value: ShellyPlugDisplay.formatPower(snapshot.totalPower), label: "Gesamtleistung", tint: .shellyAccent)
                    metricBlock(value: "\(snapshot.onCount) von \(snapshot.deviceCount)", label: "An", tint: .green)
                }
            }

            if let statusMessage = shellyStatusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Medium family only — a single slim row instead of the full section, since medium has no
    /// room below the PV/Wärmepumpe row for a third multi-line block (F16.3).
    @ViewBuilder
    private var shellyCompactRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "powerplug.fill")
                .font(.caption)
                .foregroundStyle(.shellyAccent)
            if let snapshot = entry.shellySnapshot {
                Text(ShellyPlugDisplay.formatPower(snapshot.totalPower))
                    .font(.caption.bold())
                Text("\(snapshot.onCount) von \(snapshot.deviceCount) an")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if let statusMessage = shellyStatusMessage {
                Text(statusMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
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

    /// `.notConfigured`/`.noDevices` never reach here — `showsShellySection` hides the section
    /// entirely for those two states.
    private var shellyStatusMessage: String? {
        switch entry.shellyState {
        case .ready: return nil
        case .notConfigured, .noDevices: return nil
        case .authFailed: return "Schlüssel abgelehnt — App öffnen"
        case .error: return entry.shellySnapshot == nil ? "Keine Verbindung" : "Zuletzt aktualisiert"
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
        .description("Produktion, Autarkiegrad, Anlagendruck, Außentemperatur und — sofern eingerichtet — Shelly-Steckdosen in einer Kachel.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

#Preview("Mittel", as: .systemMedium) {
    CombinedWidget()
} timeline: {
    CombinedWidgetEntry(
        date: .now,
        pvSnapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, batterySocPercent: 54, fetchedAt: .now),
        pvState: .ready,
        heatPumpSnapshot: HPWidgetDataSource.Snapshot(pressureBar: 1.4, outsideTemperatureCelsius: 8.0, fetchedAt: .now),
        heatPumpState: .ready,
        shellySnapshot: ShellyWidgetSnapshot(totalPower: 142, onCount: 2, deviceCount: 4, offlineCount: 1, plugs: [], fetchedAt: .now),
        shellyState: .ready
    )
    // Ohne Shelly eingerichtet — die dritte Zeile/Sektion entfällt vollständig, die Kachel sieht
    // exakt wie vor F16.3 aus.
    CombinedWidgetEntry(
        date: .now,
        pvSnapshot: nil, pvState: .notSignedIn,
        heatPumpSnapshot: nil, heatPumpState: .notSignedIn,
        shellySnapshot: nil, shellyState: .notConfigured
    )
}

#Preview("Groß", as: .systemLarge) {
    CombinedWidget()
} timeline: {
    CombinedWidgetEntry(
        date: .now,
        pvSnapshot: PVWidgetDataSource.Snapshot(producedWh: 4200, selfSufficiencyRate: 0.62, batterySocPercent: 54, fetchedAt: .now),
        pvState: .ready,
        heatPumpSnapshot: HPWidgetDataSource.Snapshot(pressureBar: 1.4, outsideTemperatureCelsius: 8.0, fetchedAt: .now),
        heatPumpState: .ready,
        shellySnapshot: ShellyWidgetSnapshot(totalPower: 142, onCount: 2, deviceCount: 4, offlineCount: 1, plugs: [], fetchedAt: .now),
        shellyState: .ready
    )
    CombinedWidgetEntry(
        date: .now,
        pvSnapshot: nil, pvState: .notSignedIn,
        heatPumpSnapshot: nil, heatPumpState: .notSignedIn,
        shellySnapshot: nil, shellyState: .notConfigured
    )
}
