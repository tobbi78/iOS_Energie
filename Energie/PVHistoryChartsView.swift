//
//  PVHistoryChartsView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Charts
import SwiftUI

/// Common shape for anything a history bar chart can plot a period of — implemented by both
/// `PVDailySample` (via `periodStart`) and `PVPeriodTotal`, matching the "PVSeriesBar" pattern
/// documented in BACKLOG.md F3.4.
private protocol PVSeriesBar {
    var periodStart: Date { get }
    var producedWh: Double { get }
    var consumedWh: Double { get }
    var exportedWh: Double { get }
}

extension PVDailySample: PVSeriesBar {
    var periodStart: Date { date }
}

extension PVPeriodTotal: PVSeriesBar {}

private struct PVSeriesPoint: Identifiable {
    let id = UUID()
    let period: Date
    let seriesLabel: String
    let valueKWh: Double
}

private func seriesColor(forLabel label: String) -> Color {
    switch label {
    case "Produktion": .pvAccent
    case "Verbrauch": .blue
    case "Einspeisung": .teal
    default: .gray
    }
}

private func points(from bars: [some PVSeriesBar], selection: PVSeriesSelection) -> [PVSeriesPoint] {
    bars.flatMap { bar -> [PVSeriesPoint] in
        var points: [PVSeriesPoint] = []
        if selection == .all || selection == .production {
            points.append(PVSeriesPoint(period: bar.periodStart, seriesLabel: "Produktion", valueKWh: bar.producedWh / 1000))
        }
        if selection == .all || selection == .consumption {
            points.append(PVSeriesPoint(period: bar.periodStart, seriesLabel: "Verbrauch", valueKWh: bar.consumedWh / 1000))
        }
        if selection == .all || selection == .feedIn {
            points.append(PVSeriesPoint(period: bar.periodStart, seriesLabel: "Einspeisung", valueKWh: bar.exportedWh / 1000))
        }
        return points
    }
}

/// One grouped bar chart for a given period granularity (day/month/year), see BACKLOG.md F3.4
/// for the underlying Swift Charts pattern (`PlottableValue.value(_:_:unit:calendar:)` +
/// `.position(by:)` for calendar-aware grouping).
private struct PVBarChart: View {
    let title: String
    let points: [PVSeriesPoint]
    let unit: Calendar.Component

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            if points.isEmpty {
                Text("Noch keine Daten für diesen Zeitraum.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Zeitraum", point.period, unit: unit),
                        y: .value("kWh", point.valueKWh)
                    )
                    .position(by: .value("Reihe", point.seriesLabel))
                    .foregroundStyle(seriesColor(forLabel: point.seriesLabel))
                }
                .frame(height: 180)
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// The three history sections (Tage/Monate/Jahre) plus the shared series picker (F3.4/F3.5).
struct PVHistoryChartsView: View {
    let dailySamples: [PVDailySample]
    let yearlySamples: [PVYearlySample]
    var displayPreferences: PVDisplayPreferences
    var now: Date = Date()

    private var lastThirtyDays: [PVDailySample] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: now)) else {
            return dailySamples
        }
        return dailySamples.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Wertreihe", selection: Binding(
                get: { displayPreferences.seriesSelection },
                set: { displayPreferences.setSeriesSelection($0) }
            )) {
                ForEach(PVSeriesSelection.allCases) { selection in
                    Text(selection.label).tag(selection)
                }
            }
            .pickerStyle(.segmented)

            PVBarChart(
                title: "Letzte 30 Tage",
                points: points(from: lastThirtyDays, selection: displayPreferences.seriesSelection),
                unit: .day
            )
            PVBarChart(
                title: "Letzte 12 Monate",
                points: points(
                    from: PVPeriodAggregation.lastTwelveMonths(dailySamples, now: now),
                    selection: displayPreferences.seriesSelection
                ),
                unit: .month
            )
            PVBarChart(
                title: "Jahre",
                points: points(
                    from: PVPeriodAggregation.years(dailySamples, archivedYears: yearlySamples, now: now),
                    selection: displayPreferences.seriesSelection
                ),
                unit: .year
            )
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}
