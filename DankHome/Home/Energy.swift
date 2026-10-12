//
//  Energy.swift
//  DankHome
//
//  What's on, for how long, and how much power it's drawing. HomeKit has no
//  standard power reading, so watts come from Eve's characteristics, which Eve
//  Energy and many other plugs report.
//

import SwiftUI

/// Eve's custom HomeKit characteristics for power metering.
enum EveCharacteristic {
    static let watts = "E863F10D-079E-48FF-8F27-9C2605A29F52"
    static let kilowattHours = "E863F10C-079E-48FF-8F27-9C2605A29F52"
}

extension Device.Kind {
    /// Kinds that are "on" while they use power, so they're worth timing.
    var usesPower: Bool { self == .outlet || self == .switch || self == .fan }
}

/// A light or device that's on right now.
struct PoweredItem: Identifiable, Equatable {
    enum Source: Equatable { case light, device(Device.Kind) }

    let id: UUID
    var key: String
    var name: String
    var roomName: String
    var source: Source
    var symbol: String
    var tint: Color
    var watts: Double?
    var since: Date?

    /// Plugs and switches left on a long time are worth a look; lights aren't flagged.
    func isLeftOn(now: Date = .now, hours: Int) -> Bool {
        guard hours > 0, source != .light, let since else { return false }
        return now.timeIntervalSince(since) >= Double(hours) * 3600
    }
}

extension HomeStore {
    /// Everything on right now: the biggest power draw first, then whatever has been on longest.
    func poweredItems() -> [PoweredItem] {
        let lightItems = lights.filter { $0.isOn && $0.isReachable }.map { light in
            PoweredItem(id: light.id, key: light.key, name: light.name, roomName: light.roomName, source: .light,
                        symbol: "lightbulb.fill", tint: light.tint, watts: nil, since: onSince[light.key])
        }
        let deviceItems = devices.filter { $0.kind.usesPower && $0.active && $0.isReachable }.map { device in
            PoweredItem(id: device.id, key: device.key, name: device.name, roomName: device.roomName,
                        source: .device(device.kind), symbol: device.symbol, tint: device.tint,
                        watts: device.watts, since: onSince[device.key])
        }
        return (deviceItems + lightItems).sorted { a, b in
            if (a.watts ?? 0) != (b.watts ?? 0) { return (a.watts ?? 0) > (b.watts ?? 0) }
            return (a.since ?? .distantFuture) < (b.since ?? .distantFuture)
        }
    }

    /// Total draw of the plugs that report power, or nil when none do.
    var totalWatts: Double? {
        let readings = devices.filter { $0.isReachable }.compactMap(\.watts)
        return readings.isEmpty ? nil : readings.reduce(0, +)
    }

    /// Plugs, switches and fans that have been on longer than the warning time.
    func leftOnDevices(hours: Int, now: Date = .now) -> [PoweredItem] {
        poweredItems().filter { $0.isLeftOn(now: now, hours: hours) }
    }

    /// Turns off a light or device from the energy list.
    func turnOff(_ item: PoweredItem) {
        switch item.source {
        case .light: setPower(false, for: item.id)
        case .device: setActive(false, for: item.id)
        }
    }
}

enum EnergyFormat {
    /// "45 min", "6 hr", "6 hr 12 min", "2 days".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(Int(seconds / 60), 0)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours >= 48 { return "\(hours / 24) days" }
        let rest = minutes % 60
        return rest == 0 || hours >= 10 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    /// "8 W", "1.5 kW".
    static func watts(_ watts: Double) -> String {
        if watts >= 1000 { return String(format: "%.1f kW", watts / 1000) }
        return "\(Int(watts.rounded())) W"
    }
}
