//
//  EnergyView.swift
//  DankHome
//

import SwiftUI

/// "What's on": every light, plug, switch and fan that's on, how long it's been on,
/// and what it's drawing. Opened by tapping the status line.
struct EnergyView: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { context in
                content(now: context.date)
            }
            .navigationTitle("What's On")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        // Power meters rarely announce changes, so read them while this is open.
        .task {
            while !Task.isCancelled {
                await home.refreshPower()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func content(now: Date) -> some View {
        let items = home.poweredItems()
        let hours = settings.prefs.leftOnWarningHours
        let devices = items.filter { $0.source != .light }
        let lights = items.filter { $0.source == .light }
        return List {
            Section {
                EnergySummary(items: items, totalWatts: home.totalWatts, leftOn: items.filter { $0.isLeftOn(now: now, hours: hours) }.count)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }
            if items.isEmpty {
                Section {
                    Label("Everything is off.", systemImage: "leaf.fill")
                        .foregroundStyle(.green)
                }
            }
            if !devices.isEmpty {
                Section("Plugs, Switches & Fans") {
                    ForEach(devices) { EnergyRow(item: $0, now: now, warnHours: hours) }
                }
            }
            if !lights.isEmpty {
                Section("Lights") {
                    ForEach(lights) { EnergyRow(item: $0, now: now, warnHours: hours) }
                }
            }
            Section {
            } footer: {
                Text("Power readings come from plugs that report them, like Eve Energy. Times are counted from when DankHome saw each thing turn on. Change the left-on warning in Settings › Dashboard.")
            }
        }
        .animation(.snappy, value: items)
    }
}

/// Big numbers at the top: total power and how many things are on.
struct EnergySummary: View {
    var items: [PoweredItem]
    var totalWatts: Double?
    var leftOn: Int

    var body: some View {
        HStack(spacing: Metrics.gap) {
            tile(value: totalWatts.map { EnergyFormat.watts($0) } ?? "—", label: "Using now", symbol: "bolt.fill", tint: .yellow)
            tile(value: "\(items.count)", label: items.count == 1 ? "Thing on" : "Things on", symbol: "power", tint: .cyan)
            tile(value: "\(leftOn)", label: "Left on", symbol: "exclamationmark.triangle.fill", tint: leftOn > 0 ? .orange : .gray)
        }
        .padding(.vertical, 4)
    }

    private func tile(value: String, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(white: 0.15), in: .rect(cornerRadius: 16))
    }
}

struct EnergyRow: View {
    @Environment(HomeStore.self) private var home
    var item: PoweredItem
    var now: Date
    var warnHours: Int

    var body: some View {
        let leftOn = item.isLeftOn(now: now, hours: warnHours)
        HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.tint)
                .frame(width: 34, height: 34)
                .background(item.tint.opacity(0.18), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                HStack(spacing: 4) {
                    Text(item.roomName)
                    if let since = item.since {
                        Text("·")
                        Text("On \(EnergyFormat.duration(now.timeIntervalSince(since)))")
                            .foregroundStyle(leftOn ? .orange : .secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            if let watts = item.watts {
                Text(EnergyFormat.watts(watts))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Button {
                Feedback.tap()
                withAnimation(.snappy) { home.turnOff(item) }
            } label: {
                Image(systemName: "power")
                    .font(.subheadline.weight(.bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Turn off \(item.name)")
        }
    }
}
