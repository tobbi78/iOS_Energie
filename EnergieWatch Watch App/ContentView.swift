//
//  ContentView.swift
//  EnergieWatch Watch App
//
//  Created by Tobias Florian on 04.10.26.
//
//  Two compact cards (PV, heat pump) showing whatever WatchConnectivityReceiver last received
//  from the iPhone — this Watch app never calls Enphase/Viessmann itself (see BACKLOG.md,
//  "Zielplattform Apple Watch"). Values older than an hour are shown dimmed rather than hidden,
//  so a stale reading is still visible but clearly marked as such.

import SwiftUI

private let staleAfter: TimeInterval = 3600

struct ContentView: View {
    @State private var receiver = WatchConnectivityReceiver()

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                pvCard
                heatPumpCard
            }
            .padding(.horizontal, 2)
        }
        .navigationTitle("Energie")
    }

    private var snapshot: WatchSnapshot { receiver.snapshot }

    @ViewBuilder
    private var pvCard: some View {
        let isStale = isStale(snapshot.pvFetchedAt)
        VStack(alignment: .leading, spacing: 4) {
            Label("PV-Anlage", systemImage: "sun.max.fill")
                .font(.headline)
                .foregroundStyle(.pvAccent)

            if let producedTodayWh = snapshot.pvProducedTodayWh {
                Text(Measurement(value: producedTodayWh / 1000, unit: UnitEnergy.kilowattHours)
                    .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1)))))
                    .font(.title3.bold())
                if let rate = snapshot.pvSelfSufficiencyRate {
                    Text("Autarkie \(rate.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                freshnessLabel(snapshot.pvFetchedAt)
            } else {
                Text("Noch keine Daten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.pvAccent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .opacity(isStale ? 0.5 : 1)
    }

    @ViewBuilder
    private var heatPumpCard: some View {
        let isStale = isStale(snapshot.heatPumpFetchedAt)
        let alertActive = snapshot.heatPumpPressureAlertActive
        VStack(alignment: .leading, spacing: 4) {
            Label("Wärmepumpe", systemImage: "heater.vertical.fill")
                .font(.headline)
                .foregroundStyle(alertActive ? .red : .heatPumpAccent)

            if let pressure = snapshot.heatPumpPressureBar {
                Text("\(pressure.formatted(.number.precision(.fractionLength(1...2)))) bar")
                    .font(.title3.bold())
                    .foregroundStyle(alertActive ? .red : .primary)
                if let outside = snapshot.heatPumpOutsideTemperatureCelsius {
                    Text("Außen \(outside.formatted(.number.precision(.fractionLength(0))))°C")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                freshnessLabel(snapshot.heatPumpFetchedAt)
            } else {
                Text("Noch keine Daten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background((alertActive ? Color.red : Color.heatPumpAccent).opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .opacity(isStale ? 0.5 : 1)
    }

    @ViewBuilder
    private func freshnessLabel(_ date: Date?) -> some View {
        if let date {
            Text("Stand \(date, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func isStale(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Date().timeIntervalSince(date) > staleAfter
    }
}

#Preview {
    ContentView()
}
