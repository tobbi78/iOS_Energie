//
//  ShellyHistoryChartsView.swift
//  Energie
//
//  Created by Tobias Florian on 15.10.26.
//

import Charts
import SwiftData
import SwiftUI
import UIKit

extension Color {
    /// Fixed, validated categorical palette for the stacked plug series (F14.3) — eight hues in a
    /// CVD-safe order, each with its own step for light and dark mode rather than one color
    /// auto-flipped. Assigned in order, never cycled; past eight plugs the rest fold into
    /// "Weitere" (`shellySeriesOther`).
    private static let shellySeriesPalette: [(light: UInt32, dark: UInt32)] = [
        (0x2A78D6, 0x3987E5), // blue
        (0xEB6834, 0xD95926), // orange
        (0x1BAF7A, 0x199E70), // aqua
        (0xEDA100, 0xC98500), // yellow
        (0xE87BA4, 0xD55181), // magenta
        (0x008300, 0x008300), // green
        (0x4A3AA7, 0x9085E9), // violet
        (0xE34948, 0xE66767), // red
    ]

    static func shellySeries(slot: Int?) -> Color {
        guard let slot, shellySeriesPalette.indices.contains(slot) else { return shellySeriesOther }
        let entry = shellySeriesPalette[slot]
        return Color(UIColor { traits in
            .rgb(traits.userInterfaceStyle == .dark ? entry.dark : entry.light)
        })
    }

    static let shellySeriesOther = Color(UIColor.rgb(0x898781))
}

private extension UIColor {
    // A static factory rather than a `convenience init` — Xcode's preview thunking can't compile
    // `self.init` delegation.
    static func rgb(_ rgb: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// kWh with precision scaled to the magnitude — a plug's day is often well below 1 kWh and needs
/// two decimals, while a year's total in the hundreds reads calmer without any.
private func formattedKWh(_ wh: Double) -> String {
    let kWh = wh / 1000
    let maxDecimals = kWh < 10 ? 2 : (kWh < 100 ? 1 : 0)
    return "\(kWh.formatted(.number.precision(.fractionLength(0...maxDecimals)))) kWh"
}

/// One stacked bar chart for a given period granularity. Tapping/dragging selects a period: its
/// total replaces the range total in the header and the other bars dim — the touch equivalent of
/// a hover tooltip.
private struct ShellyBarChart: View {
    let title: String
    let points: [ShellyPeriodPoint]
    let series: [ShellyHistorySeries]
    let unit: Calendar.Component
    let periodFormat: Date.FormatStyle

    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalWh: Double { ShellyPeriodAggregation.totalWh(points) }

    private func isSelected(_ periodStart: Date) -> Bool {
        guard let selectedDate else { return true }
        return Calendar.current.isDate(periodStart, equalTo: selectedDate, toGranularity: unit)
    }

    private var selectedPeriod: (start: Date, wh: Double)? {
        guard let selectedDate else { return nil }
        let inPeriod = points.filter {
            Calendar.current.isDate($0.periodStart, equalTo: selectedDate, toGranularity: unit)
        }
        guard let start = inPeriod.first?.periodStart else { return nil }
        return (start, ShellyPeriodAggregation.totalWh(inPeriod))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if totalWh <= 0 {
                Text("Noch keine Daten für diesen Zeitraum.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                chart
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer()
            // No "0 kWh" headline for an empty range — a zero reads as "measured nothing" rather
            // than "nothing recorded yet" (the F12.3 confusion).
            if totalWh > 0 {
                headlineFigure
            }
        }
    }

    private var headlineFigure: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(selectedPeriod.map { formattedKWh($0.wh) } ?? formattedKWh(totalWh))
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(selectedPeriod.map { $0.start.formatted(periodFormat) } ?? "Gesamt")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selectedPeriod?.start)
    }

    private var chart: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Zeitraum", point.periodStart, unit: unit),
                y: .value("kWh", point.energyWh / 1000)
            )
            .foregroundStyle(by: .value("Steckdose", point.seriesName))
            .opacity(isSelected(point.periodStart) ? 1 : 0.35)
            .accessibilityLabel("\(point.seriesName), \(point.periodStart.formatted(periodFormat))")
            .accessibilityValue(formattedKWh(point.energyWh))
        }
        .chartForegroundStyleScale(
            domain: series.map(\.name),
            range: series.map { Color.shellySeries(slot: $0.colorSlot) }
        )
        // A single plug needs no legend — the screen already says whose consumption this is.
        .chartLegend(series.count > 1 ? .visible : .hidden)
        .chartLegend(position: .bottom, alignment: .leading)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let kWh = value.as(Double.self) {
                        Text(kWh.formatted(.number.precision(.fractionLength(0...1))))
                    }
                }
            }
        }
        .chartYAxisLabel("kWh", position: .topLeading)
        .chartXSelection(value: $selectedDate)
        .frame(height: 200)
    }
}

/// The Shelly history sections (Tage/Monate/Jahre), F14.3. Only plugs that are currently saved
/// are charted; their history starts on the day of setup, without any backfill.
struct ShellyHistoryChartsView: View {
    let samples: [ShellyDailySample]
    let devices: [ShellyDevice]
    var now: Date = Date()

    private var series: [ShellyHistorySeries] { ShellyPeriodAggregation.series(for: devices) }

    private var hasAnyData: Bool {
        let savedIDs = Set(devices.map(\.id))
        return samples.contains { savedIDs.contains($0.deviceID) && $0.energyWh > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasAnyData {
                charts
            } else {
                // Three empty chart cards would only repeat "no data" — until the first real
                // consumption is recorded, the hint alone explains what's going on.
                collectingHint
            }
        }
        .padding(.horizontal)
        .padding(.bottom)
    }

    @ViewBuilder
    private var charts: some View {
        ShellyBarChart(
            title: "Letzte 30 Tage",
            points: ShellyPeriodAggregation.lastThirtyDays(samples, devices: devices, now: now),
            series: series,
            unit: .day,
            periodFormat: .dateTime.day().month(.abbreviated)
        )
        ShellyBarChart(
            title: "Letzte 12 Monate",
            points: ShellyPeriodAggregation.lastTwelveMonths(samples, devices: devices, now: now),
            series: series,
            unit: .month,
            periodFormat: .dateTime.month(.wide).year()
        )
        ShellyBarChart(
            title: "Jahre",
            points: ShellyPeriodAggregation.years(samples, devices: devices, now: now),
            series: series,
            unit: .year,
            periodFormat: .dateTime.year()
        )
    }

    private var collectingHint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(.shellyAccent)
                .symbolEffect(.pulse, options: .repeating)
            VStack(alignment: .leading, spacing: 4) {
                Text("Verlauf wird aufgebaut")
                    .font(.headline)
                Text("Shelly speichert keine Historie. Die App zeichnet den Verbrauch deshalb selbst auf, solange sie geöffnet ist — ab dem Tag der Einrichtung.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.shellyAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Previews

@MainActor
private func previewSamples(devices: [ShellyDevice], days: Int, now: Date) -> [ShellyDailySample] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now)
    let baseWh: [Double] = [1800, 650, 320, 120]
    return (0..<days).flatMap { offset -> [ShellyDailySample] in
        guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return [] }
        return devices.enumerated().map { index, device in
            let variation = 0.7 + 0.6 * abs(sin(Double(offset * (index + 2)) / 3))
            return ShellyDailySample(deviceID: device.id, date: day, energyWh: baseWh[index % baseWh.count] * variation)
        }
    }
}

private let previewDevices = [
    ShellyDevice(id: "a", name: "Waschmaschine", model: nil),
    ShellyDevice(id: "b", name: "Kühlschrank", model: nil),
    ShellyDevice(id: "c", name: "Büro", model: nil),
    ShellyDevice(id: "d", name: "Aquarium", model: nil),
]

#Preview("Mit Daten") {
    let container = try! ModelContainer(
        for: ShellyDailySample.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let samples = previewSamples(devices: previewDevices, days: 420, now: Date())
    samples.forEach(container.mainContext.insert)
    return NavigationStack {
        ScrollView {
            ShellyHistoryChartsView(samples: samples, devices: previewDevices)
        }
        .navigationTitle("Verlauf")
    }
    .modelContainer(container)
}

#Preview("Gerade eingerichtet") {
    let container = try! ModelContainer(
        for: ShellyDailySample.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
    )
    let samples = [ShellyDailySample(deviceID: "a", date: Calendar.current.startOfDay(for: Date()))]
    samples.forEach(container.mainContext.insert)
    return NavigationStack {
        ScrollView {
            ShellyHistoryChartsView(samples: samples, devices: Array(previewDevices.prefix(1)))
        }
        .navigationTitle("Verlauf")
    }
    .modelContainer(container)
}
