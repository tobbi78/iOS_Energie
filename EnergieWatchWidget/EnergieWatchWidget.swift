//
//  EnergieWatchWidget.swift
//  EnergieWatchWidget
//
//  Created by Tobias Florian on 04.10.26.
//
//  Watch face complications for PV + heat pump. Reads only the cached WatchSnapshot
//  (WatchSnapshotStore) that the Watch app's WatchConnectivityReceiver last wrote — this
//  extension makes no network calls of its own (see BACKLOG.md, "Zielplattform Apple Watch").
//  The four accessory families split the two energy sources across the available space:
//  circular shows the PV gauge, corner shows the heat-pump pressure gauge, rectangular combines
//  both as text, inline condenses both into one line.

import SwiftUI
import WidgetKit

struct EnergieWatchComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct EnergieWatchComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> EnergieWatchComplicationEntry {
        EnergieWatchComplicationEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (EnergieWatchComplicationEntry) -> Void) {
        completion(EnergieWatchComplicationEntry(date: Date(), snapshot: WatchSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EnergieWatchComplicationEntry>) -> Void) {
        let entry = EnergieWatchComplicationEntry(date: Date(), snapshot: WatchSnapshotStore.load())
        // WatchConnectivityReceiver calls WidgetCenter.reloadAllTimelines() on every new
        // snapshot, so this periodic refresh is just a safety net (e.g. to re-evaluate the
        // staleness dimming below even if no new snapshot arrives for a while).
        let nextRefresh = Date().addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

private let staleAfter: TimeInterval = 3600

private func isStale(_ date: Date?, relativeTo now: Date) -> Bool {
    guard let date else { return false }
    return now.timeIntervalSince(date) > staleAfter
}

struct EnergieWatchWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: EnergieWatchComplicationProvider.Entry

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            rectangularView
        }
    }

    private var snapshot: WatchSnapshot { entry.snapshot }

    @ViewBuilder
    private var circularView: some View {
        let stale = isStale(snapshot.pvFetchedAt, relativeTo: entry.date)
        Gauge(value: snapshot.pvSelfSufficiencyRate ?? 0, in: 0...1) {
            Image(systemName: "sun.max.fill")
        } currentValueLabel: {
            if let rate = snapshot.pvSelfSufficiencyRate {
                Text(rate.formatted(.percent.precision(.fractionLength(0))))
            } else {
                Text("–")
            }
        }
        .gaugeStyle(.accessoryCircular)
        .tint(.pvAccent)
        .opacity(stale ? 0.5 : 1)
    }

    @ViewBuilder
    private var cornerView: some View {
        let alertActive = snapshot.heatPumpPressureAlertActive
        let stale = isStale(snapshot.heatPumpFetchedAt, relativeTo: entry.date)
        Gauge(value: min(snapshot.heatPumpPressureBar ?? 0, 3), in: 0...3) {
            Image(systemName: "heater.vertical.fill")
        } currentValueLabel: {
            if let pressure = snapshot.heatPumpPressureBar {
                Text(pressure.formatted(.number.precision(.fractionLength(1))))
            } else {
                Text("–")
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .tint(alertActive ? .red : .heatPumpAccent)
        .widgetLabel("bar")
        .opacity(stale ? 0.5 : 1)
    }

    @ViewBuilder
    private var rectangularView: some View {
        let alertActive = snapshot.heatPumpPressureAlertActive
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sun.max.fill").foregroundStyle(.pvAccent)
                if let producedTodayWh = snapshot.pvProducedTodayWh {
                    Text(Measurement(value: producedTodayWh / 1000, unit: UnitEnergy.kilowattHours)
                        .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1)))))
                } else {
                    Text("–")
                }
            }
            .opacity(isStale(snapshot.pvFetchedAt, relativeTo: entry.date) ? 0.5 : 1)

            HStack(spacing: 4) {
                Image(systemName: "heater.vertical.fill").foregroundStyle(alertActive ? .red : .heatPumpAccent)
                if let pressure = snapshot.heatPumpPressureBar {
                    Text("\(pressure.formatted(.number.precision(.fractionLength(1...2)))) bar")
                } else {
                    Text("–")
                }
            }
            .opacity(isStale(snapshot.heatPumpFetchedAt, relativeTo: entry.date) ? 0.5 : 1)
        }
        .font(.caption2)
    }

    @ViewBuilder
    private var inlineView: some View {
        let pvText = snapshot.pvProducedTodayWh.map {
            Measurement(value: $0 / 1000, unit: UnitEnergy.kilowattHours)
                .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(1))))
        } ?? "–"
        let pressureText = snapshot.heatPumpPressureBar.map {
            "\($0.formatted(.number.precision(.fractionLength(1)))) bar"
        } ?? "–"
        Label("\(pvText) · \(pressureText)", systemImage: "bolt.fill")
    }
}

struct EnergieWatchWidget: Widget {
    let kind: String = "EnergieWatchWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: EnergieWatchComplicationProvider()) { entry in
            EnergieWatchWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Energie")
        .description("PV-Ertrag und Anlagendruck der Wärmepumpe.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

#Preview(as: .accessoryRectangular) {
    EnergieWatchWidget()
} timeline: {
    EnergieWatchComplicationEntry(date: .now, snapshot: .empty)
}
