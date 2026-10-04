//
//  SolarView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import AuthenticationServices
import SwiftData
import SwiftUI

/// Sidebar/tab section for the Enphase PV system. Structured so a sibling section for a future
/// second energy source (heat pump) can be added as its own screen later, not folded into this
/// one (see BACKLOG.md).
struct SolarView: View {
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @Query(sort: \PVDailySample.date) private var dailySamples: [PVDailySample]
    @Query private var yearlySamples: [PVYearlySample]

    var model: SolarModel
    var displayPreferences: PVDisplayPreferences

    @State private var requestsUsedThisMonth: Int?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("PV-Anlage")
                .toolbar {
                    if model.state == .ready {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                Task {
                                    await model.refresh()
                                    requestsUsedThisMonth = await model.requestsUsedThisMonth()
                                }
                            } label: {
                                Label("Aktualisieren", systemImage: "arrow.clockwise")
                            }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            NavigationLink {
                                PVHistoryScreen(
                                    dailySamples: dailySamples,
                                    yearlySamples: yearlySamples,
                                    displayPreferences: displayPreferences
                                )
                            } label: {
                                Label("Verlauf", systemImage: "chart.xyaxis.line")
                            }
                        }
                    }
                }
        }
        .task {
            // Starting the model itself now happens once in ContentView (HP-5), so it loads
            // even if the user lands on the "Start" tab first — this only refreshes the
            // displayed budget counter, a cheap local read with no network request.
            requestsUsedThisMonth = await model.requestsUsedThisMonth()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .needsCredentials:
            CredentialsFormView { clientID, clientSecret, apiKey in
                model.saveCredentials(clientID: clientID, clientSecret: clientSecret, apiKey: apiKey)
            }
        case .needsSignIn:
            SignInPromptView {
                await model.signIn(using: webAuthenticationSession)
            }
        case .loading:
            ProgressView("Lade Anlagendaten…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready:
            if let today = model.today {
                ScrollView {
                    MetricsView(sample: today, feedInTariffPerKWh: displayPreferences.feedInTariffPerKWh)
                    if let requestsUsedThisMonth {
                        Text("Enphase-Abfragen diesen Monat: \(requestsUsedThisMonth) / \(EnphaseRequestBudget.monthlyLimit)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 8)
                    }
                }
            } else {
                ProgressView("Lade Anlagendaten…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .error(let message):
            ErrorView(message: message) {
                Task { await model.refresh() }
            }
        }
    }
}

// MARK: - History submenu

/// Dedicated screen for the history charts (F3.4), reached via the toolbar instead of living
/// inline on the main PV screen, which stays focused on today's live values.
private struct PVHistoryScreen: View {
    let dailySamples: [PVDailySample]
    let yearlySamples: [PVYearlySample]
    var displayPreferences: PVDisplayPreferences

    var body: some View {
        ScrollView {
            PVHistoryChartsView(
                dailySamples: dailySamples,
                yearlySamples: yearlySamples,
                displayPreferences: displayPreferences
            )
        }
        .navigationTitle("Verlauf")
    }
}

// MARK: - Settings submenu

/// Connection status/sign-out, editable credentials, and the feed-in tariff (F6.1/F6.2). Reached
/// via the central "Einstellungen" tab (`SettingsView`), not `SolarView`'s own toolbar — hence
/// internal, not `private`.
struct PVSettingsScreen: View {
    var model: SolarModel
    var displayPreferences: PVDisplayPreferences
    var budgetSettings: EnphaseBudgetSettings

    @Environment(\.dismiss) private var dismiss
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var apiKey = ""
    @State private var tariffText = ""

    var body: some View {
        Form {
            Section("Verbindung") {
                if let systemID = model.systemID {
                    LabeledContent("Anlage", value: "\(systemID)")
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
                SecureField("Client-Secret", text: $clientSecret)
                SecureField("API-Key", text: $apiKey)
                Button("Zugangsdaten speichern") {
                    model.saveCredentials(clientID: clientID, clientSecret: clientSecret, apiKey: apiKey)
                }
                .disabled(clientID.isEmpty || clientSecret.isEmpty || apiKey.isEmpty)
            } header: {
                Text("Zugangsdaten")
            } footer: {
                Text("Ein Ändern der Zugangsdaten erfordert eine erneute Anmeldung.")
            }

            Section {
                HStack {
                    TextField("Tarif", text: $tariffText)
                        .keyboardType(.decimalPad)
                    Text("€/kWh")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Einspeisevergütung")
            } footer: {
                Text("Richtwert ohne Abrechnungsanspruch für die geschätzte Vergütung bei der Einspeisung-Kachel.")
            }

            Section {
                Stepper(
                    "Reserve: \(budgetSettings.monthlyReserve) Anfragen",
                    value: Binding(
                        get: { budgetSettings.monthlyReserve },
                        set: { budgetSettings.setMonthlyReserve($0) }
                    ),
                    in: EnphaseBudgetSettings.minimumReserve...EnphaseBudgetSettings.maximumReserve,
                    step: 5
                )
            } header: {
                Text("Monatsbudget-Reserve")
            } footer: {
                Text("Wird vom Live-Abruf-Budget zurückgehalten, damit der tägliche Abschluss-Durchlauf am Monatsende immer noch Anfragen übrig hat.")
            }
        }
        .navigationTitle("PV-Anlage")
        .onAppear {
            let credentials = model.credentials
            clientID = credentials.clientID
            clientSecret = credentials.clientSecret
            apiKey = credentials.apiKey
            tariffText = displayPreferences.feedInTariffPerKWh.formatted(.number.precision(.fractionLength(2)))
        }
        .onChange(of: tariffText) { _, newValue in
            guard let value = Double(newValue.replacingOccurrences(of: ",", with: ".")), value > 0 else { return }
            displayPreferences.setFeedInTariffPerKWh(value)
        }
    }
}

// MARK: - Credentials

private struct CredentialsFormView: View {
    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var apiKey = ""
    let onSave: (String, String, String) -> Void

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Enphase-Zugangsdaten", systemImage: "key.horizontal.fill")
                        .font(.headline)
                        .foregroundStyle(.pvAccent)
                    Text("Aus deiner Developer-App im Enphase-Portal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Zugangsdaten") {
                TextField("Client-ID", text: $clientID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Client-Secret", text: $clientSecret)
                SecureField("API-Key", text: $apiKey)
            }
            Section {
                Button("Weiter") {
                    onSave(clientID, clientSecret, apiKey)
                }
                .disabled(clientID.isEmpty || clientSecret.isEmpty || apiKey.isEmpty)
            }
        }
    }
}

// MARK: - Sign in

private struct SignInPromptView: View {
    let onSignIn: () async -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 56))
                .foregroundStyle(.pvAccent)
            Text("Mit Enphase verbinden")
                .font(.title2.bold())
            Text("Melde dich einmalig an, um die Werte deiner PV-Anlage abzurufen.")
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
            .tint(.pvAccent)
            .padding(.horizontal, 48)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Metrics

private struct MetricsView: View {
    let sample: PVDailySample
    let feedInTariffPerKWh: Double

    private var columns: [GridItem] {
        [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            MetricCard(
                title: "Autarkiegrad",
                value: sample.selfSufficiencyRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                icon: "leaf.fill",
                tint: .green
            )
            MetricCard(
                title: "Produktion",
                value: formattedKWh(sample.producedWh),
                icon: "sun.max.fill",
                tint: .pvAccent
            )
            MetricCard(
                title: "Verbrauch",
                value: formattedKWh(sample.consumedWh),
                icon: "house.fill",
                tint: .blue
            )
            MetricCard(
                title: "Einspeisung",
                value: formattedKWh(sample.exportedWh),
                subtitle: "≈ \(sample.estimatedFeedInRevenue(tariffPerKWh: feedInTariffPerKWh).formatted(.currency(code: "EUR")))",
                icon: "bolt.horizontal.fill",
                tint: .teal
            )
        }
        .padding()

        BatteryCard(sample: sample)
            .padding(.horizontal)
            .padding(.bottom)
    }

    private func formattedKWh(_ wh: Double) -> String {
        (wh / 1000).formatted(.number.precision(.fractionLength(1))) + " kWh"
    }
}

private struct BatteryCard: View {
    let sample: PVDailySample

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Speicherzustand", systemImage: "battery.100percent")
                .font(.headline)
                .foregroundStyle(.purple)

            if let soc = sample.batterySocPercent {
                ProgressView(value: soc, total: 100)
                    .tint(.purple)
                Text(soc.formatted(.number.precision(.fractionLength(0))) + " % geladen")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Ladezustand aktuell nicht verfügbar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Label((sample.batteryChargedWh / 1000).formatted(.number.precision(.fractionLength(1))) + " kWh geladen", systemImage: "arrow.down.circle")
                Spacer()
                Label((sample.batteryDischargedWh / 1000).formatted(.number.precision(.fractionLength(1))) + " kWh entladen", systemImage: "arrow.up.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

