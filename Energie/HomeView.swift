//
//  HomeView.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import SwiftUI

/// Central Home screen (HP-5): combined KPIs from all three energy/consumption sources, each
/// tappable to jump into its own tab. Deliberately does not compute anything that correlates
/// the sources (e.g. "PV surplus covers X% of heat-pump demand") — that would undermine the
/// explicit per-source independence the rest of the app relies on (see
/// Plans/Waermepumpe-Integration.md, Abschnitt 4).
struct HomeView: View {
    var solarModel: SolarModel?
    var heatPumpModel: HeatPumpModel?
    var shellyModel: ShellyModel?
    var shellyDeviceList: ShellyDeviceList
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HomeSection(title: "PV-Anlage", icon: "sun.max.fill", tint: .pvAccent) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = .pv
                        }
                    } content: {
                        pvContent
                    }
                    HomeSection(title: "Wärmepumpe", icon: "heater.vertical.fill", tint: .heatPumpAccent) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = .heatPump
                        }
                    } content: {
                        heatPumpContent
                    }
                    HomeSection(title: "Steckdosen", icon: "powerplug.fill", tint: .shellyAccent) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            selectedTab = .shelly
                        }
                    } content: {
                        shellyContent
                    }
                }
                .padding()
            }
            .navigationTitle("Start")
        }
    }

    // F10.2: Der Wechsel zwischen "Lädt…"/Fehlertext und den Kennzahlenkarten läuft über
    // `.animation(_:value:)` auf den (bereits `Equatable`) Model-State statt über
    // `withAnimation` in `SolarModel`/`HeatPumpModel` — bleibt so auf die HomeView beschränkt,
    // ohne die Models oder `SolarView`/`HeatPumpView` zu berühren. `.transition(.opacity)` ist
    // an jedem Zweig explizit gesetzt, damit die Absicht klar ist (auch wenn Opacity bereits der
    // Standard wäre). Die gestaffelte Einblendung der Karten (F10.3, `staggeredAppear`) läuft
    // unabhängig weiter.
    @ViewBuilder
    private var pvContent: some View {
        Group {
            if let solarModel {
                switch solarModel.state {
                case .ready:
                    if let today = solarModel.today {
                        HomeKPIGrid {
                            MetricCard(
                                title: "Produktion",
                                value: formattedKWh(today.producedWh),
                                icon: "sun.max.fill",
                                tint: .pvAccent
                            )
                            .staggeredAppear(index: 0)
                            MetricCard(
                                title: "Autarkiegrad",
                                value: today.selfSufficiencyRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                                icon: "leaf.fill",
                                tint: .green
                            )
                            .staggeredAppear(index: 1)
                            if let soc = today.batterySocPercent {
                                MetricCard(
                                    title: "Batterie",
                                    value: soc.formatted(.number.precision(.fractionLength(0))) + " %",
                                    icon: "battery.100percent",
                                    tint: .purple
                                )
                                .staggeredAppear(index: 2)
                            }
                        }
                        .transition(.opacity)
                    } else {
                        HomeStatusRow(text: "Lädt…")
                            .transition(.opacity)
                    }
                case .needsCredentials, .needsSignIn:
                    HomeStatusRow(text: "Nicht angemeldet — tippe hier, um dich anzumelden.")
                        .transition(.opacity)
                case .loading:
                    HomeStatusRow(text: "Lädt…")
                        .transition(.opacity)
                case .error(let message):
                    HomeStatusRow(text: message)
                        .transition(.opacity)
                }
            } else {
                HomeStatusRow(text: "Lädt…")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: solarModel?.state)
    }

    @ViewBuilder
    private var heatPumpContent: some View {
        Group {
            if let heatPumpModel {
                switch heatPumpModel.state {
                case .ready:
                    HomeKPIGrid {
                        MetricCard(
                            title: "Außentemperatur",
                            value: formattedTemperature(heatPumpModel.currentFeatures.numericValue("heating.sensors.temperature.outside")),
                            icon: "thermometer.sun",
                            tint: .blue
                        )
                        .staggeredAppear(index: 0)
                        MetricCard(
                            title: "Warmwasser",
                            value: formattedTemperature(heatPumpModel.currentFeatures.numericValue("heating.dhw.sensors.temperature.hotWaterStorage")),
                            icon: "drop.fill",
                            tint: .orange
                        )
                        .staggeredAppear(index: 1)
                        MetricCard(
                            title: "Effizienz heute",
                            value: formattedEfficiency(HeatPumpEfficiencyDataSource.liveEfficiency(features: heatPumpModel.currentFeatures, period: .day)),
                            icon: "leaf.fill",
                            tint: .green
                        )
                        .staggeredAppear(index: 2)
                    }
                    .transition(.opacity)
                case .needsCredentials, .needsSignIn:
                    HomeStatusRow(text: "Nicht angemeldet — tippe hier, um dich anzumelden.")
                        .transition(.opacity)
                case .loading:
                    HomeStatusRow(text: "Lädt…")
                        .transition(.opacity)
                case .rateLimited(let resumeAt):
                    HomeStatusRow(text: "Anfragelimit erreicht, nächster Versuch ab \(resumeAt.formatted(date: .omitted, time: .shortened)).")
                        .transition(.opacity)
                case .error(let message):
                    HomeStatusRow(text: message)
                        .transition(.opacity)
                }
            } else {
                HomeStatusRow(text: "Lädt…")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: heatPumpModel?.state)
    }

    /// Same KPI-grid/status-row pattern as `pvContent`/`heatPumpContent`, built on the same
    /// `ShellyPlugsSummary` aggregation `ShellyPlugsSummaryCard` uses in the "Steckdosen" tab
    /// itself (`Shelly/ShellyPlugsSummary.swift`), so the numbers always agree with that screen.
    @ViewBuilder
    private var shellyContent: some View {
        Group {
            if let shellyModel {
                switch shellyModel.state {
                case .ready:
                    let summary = ShellyPlugsSummary(devices: shellyDeviceList.devices, statuses: shellyModel.statuses)
                    HomeKPIGrid {
                        MetricCard(
                            title: "Leistung",
                            value: ShellyPlugDisplay.formatPower(summary.totalPower),
                            icon: "bolt.fill",
                            tint: .shellyAccent
                        )
                        .staggeredAppear(index: 0)
                        MetricCard(
                            title: "Eingeschaltet",
                            value: "\(summary.onCount) von \(summary.deviceCount)",
                            icon: "power",
                            tint: .green
                        )
                        .staggeredAppear(index: 1)
                        if summary.offlineCount > 0 {
                            MetricCard(
                                title: "Offline",
                                value: "\(summary.offlineCount)",
                                icon: "wifi.slash",
                                tint: .secondary
                            )
                            .staggeredAppear(index: 2)
                        }
                    }
                    .transition(.opacity)
                case .needsCredentials:
                    HomeStatusRow(text: "Keine Zugangsdaten — tippe hier, um sie in den Einstellungen zu hinterlegen.")
                        .transition(.opacity)
                case .noDevices:
                    HomeStatusRow(text: "Noch keine Steckdosen hinzugefügt.")
                        .transition(.opacity)
                case .loading:
                    HomeStatusRow(text: "Lädt…")
                        .transition(.opacity)
                case .authFailed:
                    HomeStatusRow(text: "Shelly-Schlüssel ungültig — bitte in den Einstellungen erneuern.")
                        .transition(.opacity)
                case .error(let message):
                    HomeStatusRow(text: message)
                        .transition(.opacity)
                }
            } else {
                HomeStatusRow(text: "Lädt…")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shellyModel?.state)
    }

    private func formattedKWh(_ wh: Double) -> String {
        (wh / 1000).formatted(.number.precision(.fractionLength(1))) + " kWh"
    }

    private func formattedTemperature(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return celsius.formatted(.number.precision(.fractionLength(1))) + " °C"
    }

    private func formattedEfficiency(_ ratio: Double?) -> String {
        guard let ratio else { return "–" }
        return ratio.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Section

private struct HomeSection<Content: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let onTap: () -> Void
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onTap) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.title3.bold())
                        .foregroundStyle(tint)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(PressableHeaderButtonStyle())
            content
        }
    }
}

/// Press feedback for the `HomeSection` headers (F10.5): a slight shrink plus fade while held,
/// so tapping into "PV-Anlage"/"Wärmepumpe" doesn't feel like tapping dead text. With "Bewegung
/// reduzieren" active, only the fade plays — no scale.
private struct PressableHeaderButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

private struct HomeKPIGrid<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            content
        }
    }
}

private struct HomeStatusRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
