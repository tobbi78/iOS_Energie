//
//  ContentView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftData
import SwiftUI

/// App root. A `TabView` so PV and the heat pump (HP-3) stay independent sections — see
/// BACKLOG.md ("Zukünftige zweite Energiequelle: Wärmepumpe") and
/// Plans/Waermepumpe-Integration.md (Abschnitt 4). A combined "Start" tab (HP-5) is a later slice.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var enphaseSettings = EnphaseSettings()
    @State private var displayPreferences = PVDisplayPreferences()
    @State private var solarModel: SolarModel?
    @State private var viessmannSettings = ViessmannSettings()
    @State private var heatPumpModel: HeatPumpModel?

    var body: some View {
        TabView {
            Tab("PV-Anlage", systemImage: "sun.max.fill") {
                if let solarModel {
                    SolarView(model: solarModel, displayPreferences: displayPreferences)
                } else {
                    ProgressView()
                }
            }
            Tab("Wärmepumpe", systemImage: "heater.vertical.fill") {
                if let heatPumpModel {
                    HeatPumpView(model: heatPumpModel)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            guard solarModel == nil else { return }
            solarModel = SolarModel(
                settings: enphaseSettings,
                modelContext: modelContext,
                budget: EnphaseRequestBudget(userDefaults: SharedAppGroup.userDefaults)
            )
        }
        .task {
            guard heatPumpModel == nil else { return }
            heatPumpModel = HeatPumpModel(settings: viessmannSettings, modelContext: modelContext)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PVDailySample.self, PVYearlySample.self, HeatPumpEfficiencySample.self], inMemory: true)
}
