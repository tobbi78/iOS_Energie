//
//  HomeView.swift
//  Energie
//
//  Created by Tobias Florian on 04.10.26.
//

import SwiftUI

/// Central Home screen (HP-5): combined KPIs from both energy sources, each tappable to jump
/// into its own tab. Deliberately does not compute anything that correlates the two sources
/// (e.g. "PV surplus covers X% of heat-pump demand") — that would undermine the explicit
/// per-source independence the rest of the app relies on (see
/// Plans/Waermepumpe-Integration.md, Abschnitt 4).
struct HomeView: View {
    var solarModel: SolarModel?
    var heatPumpModel: HeatPumpModel?
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HomeSection(title: "PV-Anlage", icon: "sun.max.fill", tint: .pvAccent) {
                        selectedTab = .pv
                    } content: {
                        pvContent
                    }
                    HomeSection(title: "Wärmepumpe", icon: "heater.vertical.fill", tint: .heatPumpAccent) {
                        selectedTab = .heatPump
                    } content: {
                        heatPumpContent
                    }
                }
                .padding()
            }
            .navigationTitle("Start")
        }
    }

    @ViewBuilder
    private var pvContent: some View {
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
                        MetricCard(
                            title: "Autarkiegrad",
                            value: today.selfSufficiencyRate.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? "–",
                            icon: "leaf.fill",
                            tint: .green
                        )
                        if let soc = today.batterySocPercent {
                            MetricCard(
                                title: "Batterie",
                                value: soc.formatted(.number.precision(.fractionLength(0))) + " %",
                                icon: "battery.100percent",
                                tint: .purple
                            )
                        }
                    }
                } else {
                    HomeStatusRow(text: "Lädt…")
                }
            case .needsCredentials, .needsSignIn:
                HomeStatusRow(text: "Nicht angemeldet — tippe hier, um dich anzumelden.")
            case .loading:
                HomeStatusRow(text: "Lädt…")
            case .error(let message):
                HomeStatusRow(text: message)
            }
        } else {
            HomeStatusRow(text: "Lädt…")
        }
    }

    @ViewBuilder
    private var heatPumpContent: some View {
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
                    MetricCard(
                        title: "Warmwasser",
                        value: formattedTemperature(heatPumpModel.currentFeatures.numericValue("heating.dhw.sensors.temperature.hotWaterStorage")),
                        icon: "drop.fill",
                        tint: .orange
                    )
                    MetricCard(
                        title: "Effizienz heute",
                        value: formattedEfficiency(HeatPumpEfficiencyDataSource.liveEfficiency(features: heatPumpModel.currentFeatures, period: .day)),
                        icon: "leaf.fill",
                        tint: .green
                    )
                }
            case .needsCredentials, .needsSignIn:
                HomeStatusRow(text: "Nicht angemeldet — tippe hier, um dich anzumelden.")
            case .loading:
                HomeStatusRow(text: "Lädt…")
            case .rateLimited(let resumeAt):
                HomeStatusRow(text: "Anfragelimit erreicht, nächster Versuch ab \(resumeAt.formatted(date: .omitted, time: .shortened)).")
            case .error(let message):
                HomeStatusRow(text: message)
            }
        } else {
            HomeStatusRow(text: "Lädt…")
        }
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
            .buttonStyle(.plain)
            content
        }
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
