//
//  ContentView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import SwiftData
import SwiftUI

/// App root. A `TabView` even with a single tab today, so a future heat-pump section can be
/// added as a sibling tab without restructuring the navigation (see BACKLOG.md, "Zukünftige
/// zweite Energiequelle: Wärmepumpe").
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings = EnphaseSettings()
    @State private var displayPreferences = PVDisplayPreferences()
    @State private var solarModel: SolarModel?

    var body: some View {
        TabView {
            Tab("PV-Anlage", systemImage: "sun.max.fill") {
                if let solarModel {
                    SolarView(model: solarModel, displayPreferences: displayPreferences)
                } else {
                    ProgressView()
                }
            }
        }
        .task {
            guard solarModel == nil else { return }
            solarModel = SolarModel(
                settings: settings,
                modelContext: modelContext,
                budget: EnphaseRequestBudget(userDefaults: SharedAppGroup.userDefaults)
            )
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [PVDailySample.self, PVYearlySample.self], inMemory: true)
}
