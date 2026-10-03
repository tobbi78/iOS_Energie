//
//  HeatPumpView.swift
//  Energie
//
//  Created by Tobias Florian on 03.10.26.
//

import AuthenticationServices
import Charts
import SwiftData
import SwiftUI

/// Overview screen for the Viessmann heat pump (HP-3/HP-4). Anlagendruck-Benachrichtigungen and
/// the Verdichter/Kältekreis-Diagnoseansicht are deliberately deferred (see
/// Plans/Waermepumpe-Integration.md, "Spätere Ausbaustufen").
struct HeatPumpView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Query(sort: \HeatPumpEfficiencySample.boundaryDate) private var efficiencySamples: [HeatPumpEfficiencySample]

    var model: HeatPumpModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Wärmepumpe")
                .toolbar {
                    if model.state == .ready {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task { await model.refresh() }
                            } label: {
                                Label("Aktualisieren", systemImage: "arrow.clockwise")
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Menu {
                                NavigationLink {
                                    HeatPumpCircuitsScreen(features: model.currentFeatures)
                                } label: {
                                    Label("Heizkreise", systemImage: "thermometer.medium")
                                }
                                NavigationLink {
                                    HeatPumpHotWaterScreen(features: model.currentFeatures)
                                } label: {
                                    Label("Warmwasser", systemImage: "drop.fill")
                                }
                                NavigationLink {
                                    HeatPumpEfficiencyScreen(features: model.currentFeatures, samples: efficiencySamples)
                                } label: {
                                    Label("Effizienz & Verbrauch", systemImage: "chart.xyaxis.line")
                                }
                                NavigationLink {
                                    HeatPumpSettingsScreen(model: model)
                                } label: {
                                    Label("Einstellungen", systemImage: "gearshape")
                                }
                            } label: {
                                Label("Mehr", systemImage: "ellipsis.circle")
                            }
                        }
                    }
                }
        }
        .task {
            await model.start()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .needsCredentials:
            ViessmannCredentialsFormView { clientID in
                model.saveCredentials(clientID: clientID)
            }
        case .needsSignIn:
            ViessmannSignInPromptView {
                await model.signIn(using: webAuthenticationSession)
            }
        case .loading:
            ProgressView("Lade Wärmepumpendaten…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            ScrollView {
                HeatPumpMetricsView(features: model.currentFeatures)
            }
        case .rateLimited(let resumeAt):
            RateLimitedView(resumeAt: resumeAt) {
                Task { await model.refresh() }
            }
        case .error(let message):
            ErrorView(message: message) {
                Task { await model.refresh() }
            }
        }
    }
}

// MARK: - Credentials

private struct ViessmannCredentialsFormView: View {
    @State private var clientID = ""
    let onSave: (String) -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Viessmann-Zugangsdaten", systemImage: "key.horizontal.fill")
                        .font(.headline)
                        .foregroundStyle(.heatPumpAccent)
                    Text("Die Client-ID aus dem Viessmann Developer Portal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Zugangsdaten") {
                TextField("Client-ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                Button("Weiter") {
                    onSave(clientID)
                }
                .disabled(clientID.isEmpty)
            }
        }
    }
}

// MARK: - Sign in

private struct ViessmannSignInPromptView: View {
    let onSignIn: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "heater.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(.heatPumpAccent)
            Text("Mit Viessmann verbinden")
                .font(.title2.bold())
            Text("Melde dich einmalig an, um die Werte deiner Wärmepumpe abzurufen.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await onSignIn() }
            } label: {
                Text("Anmelden")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.heatPumpAccent)
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rate limited

private struct RateLimitedView: View {
    let resumeAt: Date
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 44))
                .foregroundStyle(.heatPumpAccent)
            Text("Viessmann-Anfragelimit erreicht")
                .font(.headline)
            Text("Nächster Versuch ab \(resumeAt.formatted(date: .omitted, time: .shortened)) möglich.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Jetzt erneut versuchen", action: onRetry)
                .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Metrics

private struct HeatPumpMetricsView: View {
    let features: [ViessmannFeatureDTO]

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MetricCard(
                title: "Außentemperatur",
                value: formattedTemperature(features.numericValue("heating.sensors.temperature.outside")),
                icon: "thermometer.sun",
                tint: .blue
            )
            MetricCard(
                title: "Warmwasser",
                value: formattedTemperature(features.numericValue("heating.dhw.sensors.temperature.hotWaterStorage")),
                icon: "drop.fill",
                tint: .orange
            )
            MetricCard(
                title: "Elektrische Leistung",
                value: formattedPower(features.numericValue("heating.power.consumption.current")),
                icon: "bolt.fill",
                tint: .yellow
            )
            MetricCard(
                title: "Wärmeleistung",
                value: formattedPower(features.numericValue("heating.heat.production.current")),
                icon: "flame.fill",
                tint: .heatPumpAccent
            )
            MetricCard(
                title: "Effizienz heute",
                value: formattedEfficiency(HeatPumpEfficiencyDataSource.liveEfficiency(features: features, period: .day)),
                subtitle: "Wärme je kWh Strom",
                icon: "leaf.fill",
                tint: .green
            )
        }
        .padding()
    }

    private func formattedTemperature(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return celsius.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private func formattedPower(_ kilowatt: Double?) -> String {
        guard let kilowatt else { return "–" }
        return kilowatt.formatted(.number.precision(.fractionLength(1))) + " kW"
    }

    private func formattedEfficiency(_ ratio: Double?) -> String {
        guard let ratio else { return "–" }
        return ratio.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Heizkreise

/// One card per heating circuit, discovered dynamically from `heating.circuits`'s `enabled`
/// property (a comma-separated index list, e.g. "0,1") rather than assuming a fixed count —
/// devices with a single circuit or more than two work the same way. Ported from the macOS
/// sibling project's `HeatingCircuitsView`.
private struct HeatPumpCircuitsScreen: View {
    let features: [ViessmannFeatureDTO]

    private var indices: [Int] { features.enabledIndices("heating.circuits") }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if indices.isEmpty {
                    Text("Keine Heizkreise gefunden.")
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ForEach(indices, id: \.self) { index in
                        HeatPumpCircuitCard(index: index, features: features)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Heizkreise")
    }
}

private struct HeatPumpCircuitCard: View {
    let index: Int
    let features: [ViessmannFeatureDTO]

    private func key(_ suffix: String = "") -> String {
        "heating.circuits.\(index)\(suffix)"
    }

    var body: some View {
        DetailCard(title: features.stringValue(key(".name"), "name") ?? "Heizkreis \(index + 1)") {
            InfoRow(label: "Status", value: features.numericValue(key(), "active") == 1.0 ? "Aktiv" : "Inaktiv")
            InfoRow(label: "Betriebsmodus", value: features.stringValue(key(".operating.modes.active"), "value") ?? "–")
            InfoRow(label: "Aktives Programm", value: features.stringValue(key(".operating.programs.active"), "value") ?? "–")
            InfoRow(label: "Vorlauftemperatur", value: formattedMeasurement(features.numericValue(key(".sensors.temperature.supply")), unit: "°C"))
            InfoRow(label: "Heizkreispumpe", value: features.stringValue(key(".circulation.pump"), "status") ?? "–")
            InfoRow(label: "Frostschutz", value: features.stringValue(key(".frostprotection"), "status") ?? "–")
            InfoRow(label: "Heizkurve", value: heatingCurve)
            InfoRow(label: "Temperaturgrenzen", value: temperatureLevels)
        }
    }

    private var heatingCurve: String {
        guard let slope = features.numericValue(key(".heating.curve"), "slope"),
              let shift = features.numericValue(key(".heating.curve"), "shift") else {
            return "–"
        }
        return "Steigung \(slope.formatted(.number.precision(.fractionLength(0...1)))), Verschiebung \(shift.formatted(.number.precision(.fractionLength(0...1))))"
    }

    private var temperatureLevels: String {
        guard let min = features.numericValue(key(".temperature.levels"), "min"),
              let max = features.numericValue(key(".temperature.levels"), "max") else {
            return "–"
        }
        return "\(min.formatted(.number.precision(.fractionLength(0...0))))–\(max.formatted(.number.precision(.fractionLength(0...0)))) °C"
    }
}

// MARK: - Warmwasser

/// Ported from the macOS sibling project's `DomesticHotWaterView`.
private struct HeatPumpHotWaterScreen: View {
    let features: [ViessmannFeatureDTO]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                DetailCard(title: "Warmwasser") {
                    InfoRow(label: "Temperatur (Speicher)", value: formattedMeasurement(features.numericValue("heating.dhw.sensors.temperature.hotWaterStorage"), unit: "°C"))
                    InfoRow(label: "Solltemperatur", value: formattedMeasurement(features.numericValue("heating.dhw.temperature.main"), unit: "°C"))
                    InfoRow(label: "Betriebsmodus", value: features.stringValue("heating.dhw.operating.modes.active", "value") ?? "–")
                    InfoRow(label: "Status", value: features.stringValue("heating.dhw", "status") ?? "–")
                    InfoRow(label: "Zirkulationspumpe", value: features.stringValue("heating.dhw.pumps.circulation", "status") ?? "–")
                    InfoRow(label: "Verbrühschutz", value: features.numericValue("heating.dhw.scaldProtection", "active") == 1.0 ? "Aktiv" : "Inaktiv")
                }
            }
            .padding()
        }
        .navigationTitle("Warmwasser")
    }
}

// MARK: - Effizienz & Verbrauch

/// Ported from the macOS sibling project's `EfficiencyView`, combined with its Energie tab's
/// `.day` stat (that project splits "Energie" and "Effizienz" into two tabs; this app shows all
/// four periods in one screen).
private struct HeatPumpEfficiencyScreen: View {
    let features: [ViessmannFeatureDTO]
    let samples: [HeatPumpEfficiencySample]

    private static let displayedPeriods: [HeatPumpEfficiencyPeriod] = [.day, .week, .month, .year]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    ForEach(Self.displayedPeriods) { period in
                        StatCard(title: period.displayName, value: formattedEfficiency(currentValue(for: period)))
                    }
                }

                ForEach(Self.displayedPeriods) { period in
                    HeatPumpEfficiencyTrendChart(period: period, samples: samples(for: period))
                }
            }
            .padding()
        }
        .navigationTitle("Effizienz & Verbrauch")
    }

    private func samples(for period: HeatPumpEfficiencyPeriod) -> [HeatPumpEfficiencySample] {
        samples.filter { $0.period == period.rawValue }
    }

    /// Uses the latest stored snapshot when one exists; otherwise computes live from the current
    /// poll so the card doesn't show "–" before the first snapshot has ever been captured.
    private func currentValue(for period: HeatPumpEfficiencyPeriod) -> Double? {
        if let latest = samples(for: period).last {
            return latest.efficiency
        }
        return HeatPumpEfficiencyDataSource.liveEfficiency(features: features, period: period)
    }

    private func formattedEfficiency(_ ratio: Double?) -> String {
        guard let ratio else { return "–" }
        return ratio.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct HeatPumpEfficiencyTrendChart: View {
    let period: HeatPumpEfficiencyPeriod
    let samples: [HeatPumpEfficiencySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(period.displayName)
                .font(.headline)

            if samples.isEmpty {
                Text("Noch keine Werte — der erste Schnappschuss entsteht beim nächsten Abruf.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 120)
            } else {
                Chart(samples) { sample in
                    LineMark(
                        x: .value("Zeitpunkt", sample.boundaryDate),
                        y: .value("Effizienz", sample.efficiency)
                    )
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    // A lone `LineMark` draws nothing for a single data point — the symbol marks
                    // every point individually, so at least one visible dot always shows up.
                    .symbol(.circle)
                }
                .foregroundStyle(.heatPumpAccent)
                .frame(height: 120)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Einstellungen

/// Connection status/sign-out and the editable Client-ID, analogous to `PVSettingsScreen`.
private struct HeatPumpSettingsScreen: View {
    var model: HeatPumpModel

    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""

    var body: some View {
        Form {
            Section("Verbindung") {
                if let deviceSelection = model.deviceSelection {
                    LabeledContent("Installation", value: "\(deviceSelection.installationID)")
                    LabeledContent("Gerät", value: deviceSelection.deviceID)
                }
                Button("Abmelden", role: .destructive) {
                    model.signOut()
                    dismiss()
                }
            }

            Section {
                TextField("Client-ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Zugangsdaten speichern") {
                    model.saveCredentials(clientID: clientID)
                }
                .disabled(clientID.isEmpty)
            } header: {
                Text("Zugangsdaten")
            } footer: {
                Text("Ein Ändern der Client-ID erfordert eine erneute Anmeldung.")
            }
        }
        .navigationTitle("Einstellungen")
        .onAppear {
            clientID = model.credentials.clientID
        }
    }
}
