//
//  StatusLine.swift
//  DankHome
//

import SwiftUI

/// One line under the clock summing up the house: "3 lights on · Garage open · Heating to 71°".
/// Anything that needs attention (unlocked, open, jammed) is orange and comes first.
struct StatusLine: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings

    private struct Item: Identifiable {
        var id: String { text }
        var text: String
        var symbol: String?
        var alert = false
    }

    private var items: [Item] {
        var alerts: [Item] = []
        for device in home.devices where device.isReachable {
            switch device.kind {
            case .lock where !device.active || device.hasProblem:
                alerts.append(Item(text: "\(device.name) \(device.hasProblem ? "jammed" : "unlocked")", symbol: "lock.open.fill", alert: true))
            case .garage where device.active || device.hasProblem:
                alerts.append(Item(text: "\(device.name) \(device.hasProblem ? "obstructed" : "open")", symbol: "door.garage.open", alert: true))
            case .contact where device.active:
                alerts.append(Item(text: "\(device.name) open", symbol: "door.left.hand.open", alert: true))
            default:
                break
            }
        }

        if let error = home.writeError {
            alerts.insert(Item(text: error, symbol: "exclamationmark.triangle.fill", alert: true), at: 0)
        }

        var info: [Item] = []
        let on = home.lights.filter { $0.isOn && $0.isReachable }.count
        info.append(Item(text: on == 0 ? "All lights off" : on == 1 ? "1 light on" : "\(on) lights on"))
        if let thermostat = home.thermostats.first, thermostat.mode != .off {
            let target = settings.prefs.formatTemperature(celsius: thermostat.targetC)
            switch thermostat.activity {
            case .heating: info.append(Item(text: "Heating to \(target)"))
            case .cooling: info.append(Item(text: "Cooling to \(target)"))
            case .idle: info.append(Item(text: "\(thermostat.mode.title) · \(target)"))
            }
        }
        if alerts.isEmpty, home.devices.contains(where: { $0.kind == .lock }) {
            info.append(Item(text: "Doors locked", symbol: "lock.fill"))
        }
        return alerts + info
    }

    var body: some View {
        let items = items
        HStack(spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Text("·").foregroundStyle(.white.opacity(0.35)) }
                HStack(spacing: 3) {
                    if let symbol = item.symbol { Image(systemName: symbol).font(.caption2) }
                    Text(item.text)
                }
                .foregroundStyle(item.alert ? Color.orange : .white.opacity(0.6))
            }
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .animation(.snappy, value: items.map(\.text))
    }
}
