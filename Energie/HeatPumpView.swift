//
//  HeatPumpView.swift
//  Energie
//
//  Created by Tobias Florian on 03.10.26.
//

import AuthenticationServices
import SwiftUI

/// Overview screen for the Viessmann heat pump (HP-3). Detail screens (Heizkreise, Warmwasser,
/// Effizienz & Verbrauch, Anlagendruck, Verdichter/Kältekreis, Einstellungen) are a later slice
/// (HP-4) — see Plans/Waermepumpe-Integration.md.
struct HeatPumpView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

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
