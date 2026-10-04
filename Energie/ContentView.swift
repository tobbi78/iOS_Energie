//
//  ContentView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftData
import SwiftUI

/// Identifies the three top-level sections so `HomeView` can jump straight into a tab (HP-5).
enum AppTab: Hashable {
    case home, pv, heatPump
}

/// App root. A `TabView` so PV and the heat pump stay independent sections, with a combined
/// "Start" tab in front — see BACKLOG.md ("Zukünftige zweite Energiequelle: Wärmepumpe") and
/// Plans/Waermepumpe-Integration.md (Abschnitt 4).
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var enphaseSettings = EnphaseSettings()
    @State private var displayPreferences = PVDisplayPreferences()
    @State private var solarModel: SolarModel?
    @State private var viessmannSettings = ViessmannSettings()
    @State private var pressureAlertSettings = HeatPumpPressureAlertSettings()
    @State private var heatPumpModel: HeatPumpModel?
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Start", systemImage: "house.fill", value: .home) {
                HomeView(solarModel: solarModel, heatPumpModel: heatPumpModel, selectedTab: $selectedTab)
            }
            Tab("PV-Anlage", systemImage: "sun.max.fill", value: .pv) {
                if let solarModel {
                    SolarView(model: solarModel, displayPreferences: displayPreferences)
                } else {
                    ProgressView()
                }
            }
            Tab("Wärmepumpe", systemImage: "heater.vertical.fill", value: .heatPump) {
                if let heatPumpModel {
                    HeatPumpView(model: heatPumpModel)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            guard solarModel == nil else { return }
            let model = SolarModel(
                settings: enphaseSettings,
                modelContext: modelContext,
                budget: EnphaseRequestBudget(userDefaults: SharedAppGroup.userDefaults)
            )
            solarModel = model
            // Started here, not in SolarView's own .task, so the PV data loads even if the user
            // lands on the "Start" tab first and never visits "PV-Anlage" directly.
            await model.start()
        }
        .task {
            guard heatPumpModel == nil else { return }
            let model = HeatPumpModel(
                settings: viessmannSettings,
                modelContext: modelContext,
                pressureAlertSettings: pressureAlertSettings
            )
            heatPumpModel = model
            await model.start()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self], inMemory: true)
}
