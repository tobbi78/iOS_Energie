//
//  PVHistoryChartsView.swift
//  Energie
//
//  Created by Tobias Florian on 30.09.26.
//

import Charts
import SwiftUI

/// Common shape for anything a history line chart can plot a period of — implemented by both
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
    let period: Date
    let seriesLabel: String
    let valueKWh: Double

    /// Stable identity across picker/series changes (F10.6) — a fresh `UUID()` per body
    /// evaluation would keep Swift Charts from matching marks across updates, forcing a hard
    /// redraw instead of a morph/fade animation.
    var id: String { "\(seriesLabel)-\(period.timeIntervalSinceReferenceDate)" }
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

/// One line chart for a given period granularity (day/month/year). Each series becomes its own
/// line via `.foregroundStyle(by:)` — grouping by a plotted value, not just a per-mark color, is
/// what keeps Swift Charts from merging separate series into a single line (see BACKLOG.md F3.4,
/// "Falle: Mehrere LineMarks ohne unterscheidendes by:-Attribut verschmelzen").
private struct PVLineChart: View {
    let title: String
    let points: [PVSeriesPoint]
    let unit: Calendar.Component

    private static let seriesColors: KeyValuePairs<String, Color> = [
        "Produktion": .pvAccent,
        "Verbrauch": .blue,
        "Einspeisung": .teal,
    ]

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
                    LineMark(
                        x: .value("Zeitraum", point.period, unit: unit),
                        y: .value("kWh", point.valueKWh)
                    )
                    .foregroundStyle(by: .value("Reihe", point.seriesLabel))
                    .symbol(by: .value("Reihe", point.seriesLabel))
                }
                .chartForegroundStyleScale(Self.seriesColors)
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                set: { newValue in
                    // F10.6: animiert morphen/fade statt hart springen — bei aktivem
                    // "Bewegung reduzieren" (F10.3-Konsistenz) ohne Animation setzen.
                    if reduceMotion {
                        displayPreferences.setSeriesSelection(newValue)
                    } else {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            displayPreferences.setSeriesSelection(newValue)
                        }
                    }
                }
            )) {
                ForEach(PVSeriesSelection.allCases) { selection in
                    Text(selection.label).tag(selection)
                }
            }
            .pickerStyle(.segmented)

            PVLineChart(
                title: "Letzte 30 Tage",
                points: points(from: lastThirtyDays, selection: displayPreferences.seriesSelection),
                unit: .day
            )
            PVLineChart(
                title: "Letzte 12 Monate",
                points: points(
                    from: PVPeriodAggregation.lastTwelveMonths(dailySamples, now: now),
                    selection: displayPreferences.seriesSelection
                ),
                unit: .month
            )
            PVLineChart(
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
