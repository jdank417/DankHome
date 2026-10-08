//
//  HomeStore.swift
//  DankHome
//

import HomeKit
import SwiftUI

/// A single light (HomeKit lightbulb service) as the UI sees it.
struct Light: Identifiable, Equatable {
    let id: UUID
    var name: String
    var roomName: String
    var isOn: Bool
    /// 0...100, nil when the light can't dim.
    var brightness: Double?
    /// 0...360 / 0...100, nil when the light has no color.
    var hue: Double?
    var saturation: Double?
    /// White temperature in mireds (HomeKit's unit, 1,000,000 / Kelvin); nil when unsupported.
    var colorTemperature: Double?
    var colorTemperatureRange: ClosedRange<Double> = 140...500
    /// True when the light is showing white (temperature) rather than a color.
    var usesWhite = true
    var isReachable: Bool

    var supportsColor: Bool { hue != nil }

    var tint: Color {
        if !usesWhite, let hue, let saturation, saturation > 5 {
            return Color(hue: hue / 360, saturation: saturation / 100, brightness: 1)
        }
        return Self.white(kelvin: colorTemperature.map { 1_000_000 / $0 } ?? 2700)
    }

    /// Approximate on-screen color for a white temperature.
    static func white(kelvin: Double) -> Color {
        let t = ((kelvin - 2000) / 4500).clamped(to: 0...1)
        return Color(red: 1 - 0.2 * t, green: 0.68 + 0.24 * t, blue: 0.38 + 0.62 * t)
    }
}

/// A HomeKit thermostat. Temperatures are in °C, as HomeKit stores them.
struct Thermostat: Identifiable, Equatable {
    enum Mode: Int, CaseIterable, Identifiable {
        case off = 0, heat, cool, auto
        var id: Self { self }
        var title: String { ["Off", "Heat", "Cool", "Auto"][rawValue] }
        var symbol: String { ["power", "flame.fill", "snowflake", "arrow.left.arrow.right"][rawValue] }
    }

    enum Activity: Int { case idle = 0, heating, cooling }

    let id: UUID
    var name: String
    var roomName: String
    var currentC: Double?
    var targetC: Double
    var mode: Mode
    var activity: Activity
    var humidity: Double?
    var minC: Double = 10
    var maxC: Double = 32
    var isReachable: Bool

    var color: Color {
        switch (mode, activity) {
        case (.off, _): .gray
        case (_, .heating), (.heat, _): .orange
        case (_, .cooling), (.cool, _): .cyan
        default: .green
        }
    }
}

struct HomeScene: Identifiable, Equatable {
    let id: UUID
    var name: String
    var symbol: String
}

/// Wraps HMHomeManager and exposes lights, rooms and scenes for the selected home.
/// Falls back to demo data when HomeKit has no homes (e.g. in the Simulator).
@Observable
final class HomeStore: NSObject {
    private(set) var homeName = "Home"
    private(set) var roomNames: [String] = []
    private(set) var lights: [Light] = []
    private(set) var thermostats: [Thermostat] = []
    private(set) var scenes: [HomeScene] = []
    private(set) var isLoading = true
    private(set) var isDemo = false
    private(set) var authorizationProblem: String?

    /// Room shown on the dashboard; nil means every room.
    var selectedRoom: String? {
        didSet { UserDefaults.standard.set(selectedRoom, forKey: "selectedRoom") }
    }

    var visibleLights: [Light] {
        guard let selectedRoom else { return lights }
        return lights.filter { $0.roomName == selectedRoom }
    }

    var lightsOnCount: Int { visibleLights.filter(\.isOn).count }

    /// Thermostats in the selected room, or every thermostat if the room has none.
    var visibleThermostats: [Thermostat] {
        guard let selectedRoom else { return thermostats }
        let inRoom = thermostats.filter { $0.roomName == selectedRoom }
        return inRoom.isEmpty ? thermostats : inRoom
    }

    @ObservationIgnored private let manager = HMHomeManager()
    @ObservationIgnored private var services: [UUID: HMService] = [:]
    @ObservationIgnored private var actionSets: [UUID: HMActionSet] = [:]
    @ObservationIgnored private var pendingWrites: [UUID: Task<Void, Never>] = [:]

    override init() {
        selectedRoom = UserDefaults.standard.string(forKey: "selectedRoom")
        super.init()
        manager.delegate = self
    }

    // MARK: - Actions

    func toggle(_ light: Light) {
        setPower(!light.isOn, for: light.id)
    }

    func setPower(_ on: Bool, for id: UUID) {
        update(id) { $0.isOn = on }
        write(on, type: HMCharacteristicTypePowerState, to: id)
    }

    /// Updates the UI immediately; pass `commit: true` to also send to the accessory.
    func setBrightness(_ value: Double, for id: UUID, commit: Bool) {
        let value = value.rounded().clamped(to: 0...100)
        update(id) {
            $0.brightness = value
            $0.isOn = value > 0
        }
        guard commit else { return }
        if value > 0 {
            write(Int(value), type: HMCharacteristicTypeBrightness, to: id)
            write(true, type: HMCharacteristicTypePowerState, to: id)
        } else {
            write(false, type: HMCharacteristicTypePowerState, to: id)
        }
    }

    func setColor(hue: Double, saturation: Double, for id: UUID) {
        update(id) {
            $0.hue = hue
            $0.saturation = saturation
            $0.usesWhite = false
            $0.isOn = true
        }
        debounce(id) { [weak self] in
            self?.write(hue, type: HMCharacteristicTypeHue, to: id)
            self?.write(saturation, type: HMCharacteristicTypeSaturation, to: id)
            self?.write(true, type: HMCharacteristicTypePowerState, to: id)
        }
    }

    func setColor(_ color: Color, for id: UUID) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        setColor(hue: (h * 360).rounded(), saturation: (s * 100).rounded(), for: id)
    }

    /// Sets a white light temperature. Lights without white-temperature support
    /// fall back to a matching low-saturation color.
    func setWhite(kelvin: Double, for id: UUID) {
        guard let light = lights.first(where: { $0.id == id }) else { return }
        guard light.colorTemperature != nil else {
            let warmth = (1 - (kelvin - 2000) / 4500).clamped(to: 0...1)
            setColor(hue: 30, saturation: (warmth * 55).rounded(), for: id)
            update(id) { $0.usesWhite = true }
            return
        }
        let mireds = (1_000_000 / kelvin).rounded().clamped(to: light.colorTemperatureRange)
        update(id) {
            $0.colorTemperature = mireds
            $0.usesWhite = true
            $0.isOn = true
        }
        write(Int(mireds), type: HMCharacteristicTypeColorTemperature, to: id)
        write(true, type: HMCharacteristicTypePowerState, to: id)
    }

    // MARK: Thermostat

    func setTarget(_ celsius: Double, for id: UUID) {
        guard let thermostat = thermostats.first(where: { $0.id == id }) else { return }
        let value = ((celsius * 2).rounded() / 2).clamped(to: thermostat.minC...thermostat.maxC)
        updateThermostat(id) { $0.targetC = value }
        // Wait for the taps to settle before talking to the thermostat.
        debounce(id) { [weak self] in
            self?.write(value, type: HMCharacteristicTypeTargetTemperature, to: id)
        }
    }

    func setMode(_ mode: Thermostat.Mode, for id: UUID) {
        updateThermostat(id) {
            $0.mode = mode
            if isDemo {
                $0.activity = switch mode {
                case .heat: ($0.currentC ?? 0) < $0.targetC ? .heating : .idle
                case .cool: ($0.currentC ?? 0) > $0.targetC ? .cooling : .idle
                default: .idle
                }
            }
        }
        write(mode.rawValue, type: HMCharacteristicTypeTargetHeatingCooling, to: id)
    }

    private func debounce(_ id: UUID, action: @escaping () -> Void) {
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func setAllVisible(on: Bool) {
        for light in visibleLights where light.isOn != on {
            setPower(on, for: light.id)
        }
    }

    func run(_ scene: HomeScene) {
        if isDemo {
            for index in lights.indices where lights[index].isReachable {
                switch scene.symbol {
                case "sun.max.fill": lights[index].isOn = true; lights[index].brightness = lights[index].brightness.map { _ in 100 }
                case "moon.stars.fill": lights[index].isOn = false
                default: lights[index].isOn = Bool.random(); lights[index].brightness = lights[index].brightness.map { _ in 35 }
                }
            }
            return
        }
        guard let actionSet = actionSets[scene.id], let home = manager.homes.first else { return }
        Task {
            try? await home.executeActionSet(actionSet)
            await refreshValues()
        }
    }

    // MARK: - Loading

    private func reload() {
        guard let home = manager.homes.first else {
            loadDemo()
            return
        }
        isDemo = false
        homeName = home.name
        services = [:]

        var loaded: [Light] = []
        var loadedThermostats: [Thermostat] = []
        for accessory in home.accessories {
            accessory.delegate = self
            for service in accessory.services {
                switch service.serviceType {
                case HMServiceTypeLightbulb: loaded.append(makeLight(service, accessory: accessory))
                case HMServiceTypeThermostat: loadedThermostats.append(makeThermostat(service, accessory: accessory))
                default: continue
                }
                services[service.uniqueIdentifier] = service
                for characteristic in service.characteristics where characteristic.properties.contains(HMCharacteristicPropertySupportsEventNotification) {
                    characteristic.enableNotification(true) { _ in }
                }
            }
        }
        lights = loaded.sorted { ($0.roomName, $0.name) < ($1.roomName, $1.name) }
        thermostats = loadedThermostats.sorted { $0.name < $1.name }

        let roomsWithLights = Set(lights.map(\.roomName) + thermostats.map(\.roomName))
        roomNames = (home.rooms.map(\.name) + [home.roomForEntireHome().name])
            .filter { roomsWithLights.contains($0) }
        if let selectedRoom, !roomNames.contains(selectedRoom) { self.selectedRoom = nil }

        actionSets = Dictionary(uniqueKeysWithValues: home.actionSets.map { ($0.uniqueIdentifier, $0) })
        scenes = home.actionSets
            .sorted { $0.name < $1.name }
            .map { HomeScene(id: $0.uniqueIdentifier, name: $0.name, symbol: Self.symbol(for: $0)) }

        isLoading = false
        Task { await refreshValues() }
    }

    private func refreshValues() async {
        for (id, service) in services {
            for characteristic in service.characteristics where Self.trackedTypes.contains(characteristic.characteristicType) {
                try? await characteristic.readValue()
                apply(characteristic, to: id)
            }
            let reachable = service.accessory?.isReachable ?? false
            update(id) { $0.isReachable = reachable }
            updateThermostat(id) { $0.isReachable = reachable }
        }
    }

    private static let trackedTypes: Set<String> = [
        HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness,
        HMCharacteristicTypeHue, HMCharacteristicTypeSaturation, HMCharacteristicTypeColorTemperature,
        HMCharacteristicTypeCurrentTemperature, HMCharacteristicTypeTargetTemperature,
        HMCharacteristicTypeCurrentHeatingCooling, HMCharacteristicTypeTargetHeatingCooling,
        HMCharacteristicTypeCurrentRelativeHumidity,
    ]

    private func makeLight(_ service: HMService, accessory: HMAccessory) -> Light {
        let value = { (type: String) in service.number(type) }
        let has = { (type: String) in service.characteristic(type) != nil }
        var light = Light(
            id: service.uniqueIdentifier,
            name: service.name.isEmpty ? accessory.name : service.name,
            roomName: accessory.room?.name ?? "Home",
            isOn: (value(HMCharacteristicTypePowerState) ?? 0) > 0,
            brightness: has(HMCharacteristicTypeBrightness) ? value(HMCharacteristicTypeBrightness) ?? 100 : nil,
            hue: has(HMCharacteristicTypeHue) ? value(HMCharacteristicTypeHue) ?? 0 : nil,
            saturation: has(HMCharacteristicTypeSaturation) ? value(HMCharacteristicTypeSaturation) ?? 0 : nil,
            colorTemperature: has(HMCharacteristicTypeColorTemperature) ? value(HMCharacteristicTypeColorTemperature) ?? 370 : nil,
            isReachable: accessory.isReachable
        )
        if let metadata = service.characteristic(HMCharacteristicTypeColorTemperature)?.metadata,
           let low = metadata.minimumValue?.doubleValue, let high = metadata.maximumValue?.doubleValue, low < high {
            light.colorTemperatureRange = low...high
        }
        light.usesWhite = (light.saturation ?? 0) < 5
        return light
    }

    private func makeThermostat(_ service: HMService, accessory: HMAccessory) -> Thermostat {
        let target = service.characteristic(HMCharacteristicTypeTargetTemperature)
        return Thermostat(
            id: service.uniqueIdentifier,
            name: service.name.isEmpty ? accessory.name : service.name,
            roomName: accessory.room?.name ?? "Home",
            currentC: service.number(HMCharacteristicTypeCurrentTemperature),
            targetC: service.number(HMCharacteristicTypeTargetTemperature) ?? 21,
            mode: Thermostat.Mode(rawValue: Int(service.number(HMCharacteristicTypeTargetHeatingCooling) ?? 0)) ?? .off,
            activity: Thermostat.Activity(rawValue: Int(service.number(HMCharacteristicTypeCurrentHeatingCooling) ?? 0)) ?? .idle,
            humidity: service.number(HMCharacteristicTypeCurrentRelativeHumidity),
            minC: target?.metadata?.minimumValue?.doubleValue ?? 10,
            maxC: target?.metadata?.maximumValue?.doubleValue ?? 32,
            isReachable: accessory.isReachable
        )
    }

    private func apply(_ characteristic: HMCharacteristic, to id: UUID) {
        guard let number = characteristic.value as? NSNumber else { return }
        let value = number.doubleValue
        update(id) { light in
            switch characteristic.characteristicType {
            case HMCharacteristicTypePowerState: light.isOn = value > 0
            case HMCharacteristicTypeBrightness: light.brightness = value
            case HMCharacteristicTypeHue: light.hue = value
            case HMCharacteristicTypeSaturation: light.saturation = value; light.usesWhite = value < 5
            case HMCharacteristicTypeColorTemperature: light.colorTemperature = value
            default: break
            }
        }
        updateThermostat(id) { thermostat in
            switch characteristic.characteristicType {
            case HMCharacteristicTypeCurrentTemperature: thermostat.currentC = value
            case HMCharacteristicTypeTargetTemperature: thermostat.targetC = value
            case HMCharacteristicTypeTargetHeatingCooling: thermostat.mode = .init(rawValue: Int(value)) ?? .off
            case HMCharacteristicTypeCurrentHeatingCooling: thermostat.activity = .init(rawValue: Int(value)) ?? .idle
            case HMCharacteristicTypeCurrentRelativeHumidity: thermostat.humidity = value
            default: break
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Light) -> Void) {
        guard let index = lights.firstIndex(where: { $0.id == id }) else { return }
        change(&lights[index])
    }

    private func updateThermostat(_ id: UUID, _ change: (inout Thermostat) -> Void) {
        guard let index = thermostats.firstIndex(where: { $0.id == id }) else { return }
        change(&thermostats[index])
    }

    private func write(_ value: Any, type: String, to id: UUID) {
        services[id]?.characteristic(type)?.writeValue(value) { _ in }
    }

    private static func symbol(for actionSet: HMActionSet) -> String {
        switch actionSet.actionSetType {
        case HMActionSetTypeWakeUp: "sunrise.fill"
        case HMActionSetTypeSleep: "moon.stars.fill"
        case HMActionSetTypeHomeArrival: "house.fill"
        case HMActionSetTypeHomeDeparture: "figure.walk.departure"
        default:
            switch actionSet.name.lowercased() {
            case let n where n.contains("movie") || n.contains("tv"): "tv.fill"
            case let n where n.contains("relax") || n.contains("chill"): "sofa.fill"
            case let n where n.contains("dinner"): "fork.knife"
            case let n where n.contains("party"): "party.popper.fill"
            case let n where n.contains("night"): "moon.fill"
            case let n where n.contains("bright") || n.contains("day"): "sun.max.fill"
            default: "sparkles"
            }
        }
    }

    // MARK: - Demo data

    private func loadDemo() {
        isDemo = true
        homeName = "Dank Home"
        services = [:]
        actionSets = [:]
        lights = [
            Light(id: UUID(), name: "Ceiling", roomName: "Living Room", isOn: true, brightness: 80, hue: nil, saturation: nil, colorTemperature: 370, isReachable: true),
            Light(id: UUID(), name: "Floor Lamp", roomName: "Living Room", isOn: true, brightness: 45, hue: 28, saturation: 70, colorTemperature: 400, usesWhite: false, isReachable: true),
            Light(id: UUID(), name: "TV Backlight", roomName: "Living Room", isOn: false, brightness: 60, hue: 265, saturation: 85, usesWhite: false, isReachable: true),
            Light(id: UUID(), name: "Shelf Strip", roomName: "Living Room", isOn: true, brightness: 30, hue: 190, saturation: 80, usesWhite: false, isReachable: true),
            Light(id: UUID(), name: "Pendants", roomName: "Kitchen", isOn: false, brightness: 100, hue: nil, saturation: nil, isReachable: true),
            Light(id: UUID(), name: "Under Cabinet", roomName: "Kitchen", isOn: true, brightness: 70, hue: nil, saturation: nil, isReachable: true),
            Light(id: UUID(), name: "Bedside", roomName: "Bedroom", isOn: false, brightness: 20, hue: 15, saturation: 60, colorTemperature: 450, usesWhite: false, isReachable: true),
            Light(id: UUID(), name: "Porch", roomName: "Outside", isOn: false, brightness: nil, hue: nil, saturation: nil, isReachable: false),
        ]
        roomNames = ["Living Room", "Kitchen", "Bedroom", "Outside"]
        thermostats = [
            Thermostat(id: UUID(), name: "Thermostat", roomName: "Living Room", currentC: 20.5, targetC: 21.5,
                       mode: .heat, activity: .heating, humidity: 42, isReachable: true),
        ]
        scenes = [
            HomeScene(id: UUID(), name: "Bright", symbol: "sun.max.fill"),
            HomeScene(id: UUID(), name: "Relax", symbol: "sofa.fill"),
            HomeScene(id: UUID(), name: "Movie", symbol: "tv.fill"),
            HomeScene(id: UUID(), name: "Good Night", symbol: "moon.stars.fill"),
        ]
        isLoading = false
    }
}

// MARK: - HomeKit delegates

extension HomeStore: HMHomeManagerDelegate, HMAccessoryDelegate {
    func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
        if !manager.authorizationStatus.contains(.authorized), manager.authorizationStatus.contains(.determined) {
            authorizationProblem = "DankHome doesn't have access to your home. Turn it on in Settings › Privacy & Security › HomeKit."
        } else {
            authorizationProblem = nil
        }
        reload()
    }

    func accessory(_ accessory: HMAccessory, service: HMService, didUpdateValueFor characteristic: HMCharacteristic) {
        apply(characteristic, to: service.uniqueIdentifier)
    }

    func accessoryDidUpdateReachability(_ accessory: HMAccessory) {
        for service in accessory.services {
            update(service.uniqueIdentifier) { $0.isReachable = accessory.isReachable }
            updateThermostat(service.uniqueIdentifier) { $0.isReachable = accessory.isReachable }
        }
    }
}

private extension HMService {
    func characteristic(_ type: String) -> HMCharacteristic? {
        characteristics.first { $0.characteristicType == type }
    }

    func number(_ type: String) -> Double? {
        (characteristic(type)?.value as? NSNumber)?.doubleValue
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
