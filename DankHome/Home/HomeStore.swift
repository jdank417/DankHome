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
    /// Smallest change the thermostat accepts, in °C.
    var stepC: Double = 0.5
    /// In Auto, thermostats follow this heat/cool range instead of the target.
    var heatC: Double?
    var coolC: Double?
    var isReachable: Bool
    /// A new target is waiting to be sent, or sent but not yet confirmed by the thermostat.
    var isSending = false

    var color: Color {
        switch (mode, activity) {
        case (.off, _): .gray
        case (_, .heating), (.heat, _): .orange
        case (_, .cooling), (.cool, _): .cyan
        default: .green
        }
    }
}

/// Any other accessory the dashboard can show: locks, garage doors, shades, fans,
/// outlets, switches and contact sensors.
struct Device: Identifiable, Equatable {
    enum Kind: String, Codable {
        case lock, garage, shade, fan, outlet, `switch`, contact

        /// The order they appear in.
        var sortOrder: Int { [.lock, .garage, .contact, .shade, .fan, .outlet, .switch].firstIndex(of: self)! }
    }

    let id: UUID
    var name: String
    var roomName: String
    var kind: Kind
    /// Locked (lock), open (garage, shade, contact), or on (fan, outlet, switch).
    var active: Bool
    /// Shade position or fan speed, 0…100.
    var level: Double?
    /// Garage door opening/closing, or a shade moving.
    var isMoving = false
    /// Lock jammed or garage door obstructed.
    var hasProblem = false
    /// Power draw right now, from plugs that report it (e.g. Eve Energy).
    var watts: Double?
    /// Lifetime energy use in kWh, when the plug reports it.
    var energyKWh: Double?
    var isReachable: Bool

    var key: String { "\(roomName)|\(name)" }
    /// Unlocking and opening the garage ask first.
    var needsConfirmation: Bool { (kind == .lock && active) || (kind == .garage && !active) }
    var isControllable: Bool { kind != .contact }

    var symbol: String {
        switch kind {
        case .lock: active ? "lock.fill" : "lock.open.fill"
        case .garage: active ? "door.garage.open" : "door.garage.closed"
        case .shade: active ? "blinds.horizontal.open" : "blinds.horizontal.closed"
        case .fan: "fan.fill"
        case .outlet: active ? "poweroutlet.type.b.fill" : "poweroutlet.type.b"
        case .switch: active ? "switch.2" : "switch.2"
        case .contact: active ? "door.left.hand.open" : "door.left.hand.closed"
        }
    }

    var status: String {
        guard isReachable else { return "No Response" }
        switch kind {
        case .lock: return hasProblem ? "Jammed" : isMoving ? (active ? "Locking…" : "Unlocking…") : active ? "Locked" : "Unlocked"
        case .garage: return hasProblem ? "Obstructed" : isMoving ? (active ? "Opening…" : "Closing…") : active ? "Open" : "Closed"
        case .shade:
            guard let level else { return active ? "Open" : "Closed" }
            return level <= 0 ? "Closed" : level >= 100 ? "Open" : "\(Int(level))% Open"
        case .fan:
            guard active else { return "Off" }
            return level.map { "\(Int($0))%" } ?? "On"
        case .outlet, .switch: return active ? "On" : "Off"
        case .contact: return active ? "Open" : "Closed"
        }
    }

    /// Lit up when it's in its "attention" state: unlocked, open, or on.
    var isHighlighted: Bool {
        switch kind {
        case .lock: !active || hasProblem
        default: active || hasProblem
        }
    }

    var tint: Color {
        if hasProblem { return .red }
        switch kind {
        case .lock: return active ? .green : .orange
        case .garage, .contact: return active ? .orange : .green
        case .shade: return .cyan
        case .fan: return .mint
        case .outlet, .switch: return .yellow
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
    private(set) var lights: [Light] = [] {
        didSet { trackOnSince() }
    }
    private(set) var thermostats: [Thermostat] = []
    private(set) var devices: [Device] = [] {
        didSet { trackOnSince() }
    }
    /// When each light or device ("Room|Name") was last turned on. Kept across launches.
    private(set) var onSince: [String: Date] = [:]
    private(set) var scenes: [HomeScene] = []
    private(set) var isLoading = true
    private(set) var isDemo = false

    /// Show demo data even when a real home exists (Settings › Dashboard › Demo Mode).
    var forceDemo = false {
        didSet { if forceDemo != oldValue { reload() } }
    }
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

    var visibleDevices: [Device] {
        guard let selectedRoom else { return devices }
        return devices.filter { $0.roomName == selectedRoom }
    }

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
    /// Writes still on their way to an accessory, and when the last one finished. Incoming
    /// values for those characteristics are ignored meanwhile so the UI doesn't jump back.
    @ObservationIgnored private var writesInFlight: [String: Int] = [:]
    @ObservationIgnored private var lastWrite: [String: Date] = [:]
    @ObservationIgnored private var lastSent: [String: Date] = [:]
    @ObservationIgnored private var trailingSends: [String: Task<Void, Never>] = [:]
    /// The target the person chose, held until the thermostat confirms it (or 15 s pass),
    /// so slow cloud thermostats can't bounce the dial back to an older value.
    @ObservationIgnored private var heldTargets: [UUID: (value: Double, until: Date)] = [:]

    /// A short message when an accessory didn't accept a change.
    private(set) var writeError: String?
    @ObservationIgnored private var errorTask: Task<Void, Never>?
    /// While a scene button is being recorded, every light or thermostat the person touches.
    @ObservationIgnored var touched: Set<UUID>?

    override init() {
        selectedRoom = UserDefaults.standard.string(forKey: "selectedRoom")
        onSince = Self.savedOnSince()
        super.init()
        manager.delegate = self
    }

    // MARK: - Actions

    func toggle(_ light: Light) {
        setPower(!light.isOn, for: light.id)
    }

    func setPower(_ on: Bool, for id: UUID) {
        touched?.insert(id)
        update(id) { $0.isOn = on }
        write(on, type: HMCharacteristicTypePowerState, to: id)
    }

    /// Updates the UI immediately; pass `commit: true` to also send to the accessory.
    func setBrightness(_ value: Double, for id: UUID, commit: Bool) {
        touched?.insert(id)
        let value = value.rounded().clamped(to: 0...100)
        let wasOn = lights.first { $0.id == id }?.isOn ?? false
        update(id) {
            $0.brightness = value
            $0.isOn = value > 0
        }
        // While dragging, send a few updates a second so the real light follows the finger;
        // the final value always goes out when the drag ends.
        let send = { [weak self] in
            guard let self else { return }
            if value > 0 {
                self.write(Int(value), type: HMCharacteristicTypeBrightness, to: id)
                if !wasOn || commit { self.write(true, type: HMCharacteristicTypePowerState, to: id) }
            } else {
                self.write(false, type: HMCharacteristicTypePowerState, to: id)
            }
        }
        if commit {
            trailingSends["\(id)-brightness"]?.cancel()
            send()
        } else {
            throttle("\(id)-brightness", action: send)
        }
    }

    func setColor(hue: Double, saturation: Double, for id: UUID) {
        touched?.insert(id)
        update(id) {
            $0.hue = hue
            $0.saturation = saturation
            $0.usesWhite = false
            $0.isOn = true
        }
        throttle("\(id)-color") { [weak self] in
            self?.write(Float(hue), type: HMCharacteristicTypeHue, to: id)
            self?.write(Float(saturation), type: HMCharacteristicTypeSaturation, to: id)
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
        touched?.insert(id)
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

    // MARK: Devices

    /// Lock/unlock, open/close or on/off.
    func toggle(_ device: Device) {
        setActive(!device.active, for: device.id)
    }

    func setActive(_ active: Bool, for id: UUID) {
        touched?.insert(id)
        guard let device = devices.first(where: { $0.id == id }), device.isControllable else { return }
        updateDevice(id) {
            $0.active = active
            if device.kind == .shade { $0.level = active ? 100 : 0 }
            if device.kind == .fan, active, $0.level == 0 { $0.level = 100 }
            // Real locks and doors report when they finish moving.
            $0.isMoving = !isDemo && (device.kind == .lock || device.kind == .garage)
        }
        switch device.kind {
        case .lock: write(active ? 1 : 0, type: HMCharacteristicTypeTargetLockMechanismState, to: id)
        case .garage: write(active ? 0 : 1, type: HMCharacteristicTypeTargetDoorState, to: id)
        case .shade: write(active ? 100 : 0, type: HMCharacteristicTypeTargetPosition, to: id)
        case .fan:
            if services[id]?.characteristic(HMCharacteristicTypeActive) != nil {
                write(active ? 1 : 0, type: HMCharacteristicTypeActive, to: id)
            } else {
                write(active, type: HMCharacteristicTypePowerState, to: id)
            }
        case .outlet, .switch: write(active, type: HMCharacteristicTypePowerState, to: id)
        case .contact: break
        }
    }

    /// Shade position or fan speed, 0…100.
    func setLevel(_ value: Double, for id: UUID) {
        touched?.insert(id)
        guard let device = devices.first(where: { $0.id == id }) else { return }
        let value = value.rounded().clamped(to: 0...100)
        updateDevice(id) {
            $0.level = value
            $0.active = value > 0
        }
        debounce(id) { [weak self] in
            switch device.kind {
            case .shade: self?.write(Int(value), type: HMCharacteristicTypeTargetPosition, to: id)
            case .fan:
                self?.write(value, type: HMCharacteristicTypeRotationSpeed, to: id)
                if self?.services[id]?.characteristic(HMCharacteristicTypeActive) != nil {
                    self?.write(value > 0 ? 1 : 0, type: HMCharacteristicTypeActive, to: id)
                } else {
                    self?.write(value > 0, type: HMCharacteristicTypePowerState, to: id)
                }
            default: break
            }
        }
    }

    // MARK: Thermostat

    func setTarget(_ celsius: Double, for id: UUID) {
        touched?.insert(id)
        guard let thermostat = thermostats.first(where: { $0.id == id }) else { return }
        let step = thermostat.stepC > 0 ? thermostat.stepC : 0.5
        let value = ((celsius / step).rounded() * step).clamped(to: thermostat.minC...thermostat.maxC)
        let delta = value - thermostat.targetC
        updateThermostat(id) {
            $0.targetC = value
            // In Auto, move the heat/cool range with the target so the change takes effect.
            if $0.mode == .auto {
                $0.heatC = $0.heatC.map { $0 + delta }
                $0.coolC = $0.coolC.map { $0 + delta }
            }
        }
        updateThermostat(id) { $0.isSending = true }
        heldTargets[id] = (value, .now.addingTimeInterval(60))
        // Tap as much as you like; only the final number is sent, once tapping stops.
        debounce(id, after: 1.5) { [weak self] in
            guard let self, let updated = self.thermostats.first(where: { $0.id == id }) else { return }
            let deadline = Date.now.addingTimeInterval(15)
            self.heldTargets[id] = (value, deadline)
            self.write(Float(value), type: HMCharacteristicTypeTargetTemperature, to: id)
            if updated.mode == .auto {
                if let heat = updated.heatC { self.write(Float(heat), type: HMCharacteristicTypeHeatingThreshold, to: id) }
                if let cool = updated.coolC { self.write(Float(cool), type: HMCharacteristicTypeCoolingThreshold, to: id) }
            }
            // Never confirmed? After 15 s, show whatever the thermostat really has.
            Task {
                try? await Task.sleep(for: .seconds(15))
                guard self.heldTargets[id]?.until == deadline else { return }
                self.heldTargets[id] = nil
                self.updateThermostat(id) { $0.isSending = false }
                if let characteristic = self.services[id]?.characteristic(HMCharacteristicTypeTargetTemperature) {
                    try? await characteristic.readValue()
                    self.apply(characteristic, to: id)
                }
            }
        }
    }

    /// While a target is held, only a report of that same value gets through (and confirms it).
    private func acceptsTarget(_ value: Double, for id: UUID) -> Bool {
        guard let held = heldTargets[id] else { return true }
        if Date.now > held.until {
            heldTargets[id] = nil
            updateThermostat(id) { $0.isSending = false }
            return true
        }
        guard abs(value - held.value) < 0.06 else { return false }
        heldTargets[id] = nil
        updateThermostat(id) { $0.isSending = false }
        return true
    }

    /// One displayed degree up or down, in the person's units (°F moves by whole °F).
    func nudgeTarget(by degrees: Int, unit: TemperatureUnit, for id: UUID) {
        guard let thermostat = thermostats.first(where: { $0.id == id }) else { return }
        switch unit {
        case .fahrenheit:
            let current = (thermostat.targetC * 9 / 5 + 32).rounded()
            setTarget((current + Double(degrees) - 32) * 5 / 9, for: id)
        case .celsius:
            setTarget(thermostat.targetC + Double(degrees) * 0.5, for: id)
        }
    }

    func setMode(_ mode: Thermostat.Mode, for id: UUID) {
        touched?.insert(id)
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

    /// Sends at most every `interval`, always delivering the last value.
    private func throttle(_ key: String, interval: Double = 0.2, action: @escaping () -> Void) {
        trailingSends[key]?.cancel()
        let elapsed = lastSent[key].map { Date.now.timeIntervalSince($0) } ?? .infinity
        if elapsed >= interval {
            lastSent[key] = .now
            action()
        } else {
            trailingSends[key] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(interval - elapsed))
                guard !Task.isCancelled else { return }
                self?.lastSent[key] = .now
                action()
            }
        }
    }

    private func debounce(_ id: UUID, after seconds: Double = 0.4, action: @escaping () -> Void) {
        pendingWrites[id]?.cancel()
        pendingWrites[id] = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func setAllVisible(on: Bool) {
        for light in visibleLights where light.isOn != on && light.isReachable {
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
        guard !forceDemo, let home = manager.homes.first else {
            loadDemo()
            return
        }
        if isDemo { onSince = Self.savedOnSince() }
        isDemo = false
        homeName = home.name
        services = [:]

        var loaded: [Light] = []
        var loadedThermostats: [Thermostat] = []
        var loadedDevices: [Device] = []
        for accessory in home.accessories {
            accessory.delegate = self
            for service in accessory.services {
                switch service.serviceType {
                case HMServiceTypeLightbulb: loaded.append(makeLight(service, accessory: accessory))
                case HMServiceTypeThermostat: loadedThermostats.append(makeThermostat(service, accessory: accessory))
                case let type where Self.deviceKinds[type] != nil:
                    loadedDevices.append(makeDevice(service, kind: Self.deviceKinds[type]!, accessory: accessory))
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
        devices = loadedDevices.sorted { ($0.kind.sortOrder, $0.name) < ($1.kind.sortOrder, $1.name) }

        let roomsWithLights = Set(lights.map(\.roomName) + thermostats.map(\.roomName) + devices.map(\.roomName))
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

    /// Reads everything at once (not one by one) so the dashboard settles quickly.
    private func refreshValues() async {
        for (id, service) in services {
            for characteristic in service.characteristics where Self.trackedTypes.contains(characteristic.characteristicType) {
                // One task each, so all the reads happen at the same time.
                Task {
                    try? await characteristic.readValue()
                    apply(characteristic, to: id)
                }
            }
            let reachable = service.accessory?.isReachable ?? false
            update(id) { $0.isReachable = reachable }
            updateThermostat(id) { $0.isReachable = reachable }
            updateDevice(id) { $0.isReachable = reachable }
        }
    }

    private static let trackedTypes: Set<String> = [
        HMCharacteristicTypePowerState, HMCharacteristicTypeBrightness,
        HMCharacteristicTypeHue, HMCharacteristicTypeSaturation, HMCharacteristicTypeColorTemperature,
        HMCharacteristicTypeCurrentTemperature, HMCharacteristicTypeTargetTemperature,
        HMCharacteristicTypeCurrentHeatingCooling, HMCharacteristicTypeTargetHeatingCooling,
        HMCharacteristicTypeCurrentRelativeHumidity,
        HMCharacteristicTypeHeatingThreshold, HMCharacteristicTypeCoolingThreshold,
        HMCharacteristicTypeCurrentLockMechanismState, HMCharacteristicTypeTargetLockMechanismState,
        HMCharacteristicTypeCurrentDoorState, HMCharacteristicTypeTargetDoorState, HMCharacteristicTypeObstructionDetected,
        HMCharacteristicTypeCurrentPosition, HMCharacteristicTypeActive, HMCharacteristicTypeRotationSpeed,
        HMCharacteristicTypeContactState,
        EveCharacteristic.watts, EveCharacteristic.kilowattHours,
    ]

    private static let deviceKinds: [String: Device.Kind] = [
        HMServiceTypeLockMechanism: .lock, HMServiceTypeGarageDoorOpener: .garage,
        HMServiceTypeWindowCovering: .shade, HMServiceTypeFan: .fan, HMServiceTypeOutlet: .outlet,
        HMServiceTypeSwitch: .switch, HMServiceTypeContactSensor: .contact,
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
            stepC: target?.metadata?.stepValue?.doubleValue ?? 0.5,
            heatC: service.number(HMCharacteristicTypeHeatingThreshold),
            coolC: service.number(HMCharacteristicTypeCoolingThreshold),
            isReachable: accessory.isReachable
        )
    }

    private func makeDevice(_ service: HMService, kind: Device.Kind, accessory: HMAccessory) -> Device {
        var device = Device(id: service.uniqueIdentifier,
                            name: service.name.isEmpty ? accessory.name : service.name,
                            roomName: accessory.room?.name ?? "Home",
                            kind: kind, active: false, isReachable: accessory.isReachable)
        for characteristic in service.characteristics {
            Self.apply(characteristic, to: &device)
        }
        return device
    }

    /// Reads one characteristic into a device's state.
    private static func apply(_ characteristic: HMCharacteristic, to device: inout Device) {
        guard let value = (characteristic.value as? NSNumber)?.doubleValue else { return }
        switch (device.kind, characteristic.characteristicType) {
        case (.lock, HMCharacteristicTypeCurrentLockMechanismState):
            device.hasProblem = value == 2
            if value <= 1 { device.active = value == 1; device.isMoving = false }
        case (.garage, HMCharacteristicTypeCurrentDoorState):
            // 0 open, 1 closed, 2 opening, 3 closing, 4 stopped
            device.isMoving = value == 2 || value == 3
            device.active = value == 0 || value == 2 || value == 4
        case (.garage, HMCharacteristicTypeObstructionDetected):
            device.hasProblem = value > 0
        case (.shade, HMCharacteristicTypeCurrentPosition):
            device.level = value
            device.active = value > 0
        case (.fan, HMCharacteristicTypeActive), (.fan, HMCharacteristicTypePowerState),
             (.outlet, HMCharacteristicTypePowerState), (.switch, HMCharacteristicTypePowerState):
            device.active = value > 0
        case (.fan, HMCharacteristicTypeRotationSpeed):
            device.level = value
        case (.contact, HMCharacteristicTypeContactState):
            device.active = value == 1  // 1 = contact not detected = open
        case (_, EveCharacteristic.watts):
            device.watts = value
        case (_, EveCharacteristic.kilowattHours):
            device.energyKWh = value
        default:
            break
        }
    }

    private func apply(_ characteristic: HMCharacteristic, to id: UUID) {
        guard !isSettling(characteristic, id: id) else { return }
        updateDevice(id) { Self.apply(characteristic, to: &$0) }
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
        let acceptTarget = characteristic.characteristicType == HMCharacteristicTypeTargetTemperature
            && thermostats.contains(where: { $0.id == id }) ? acceptsTarget(value, for: id) : true
        updateThermostat(id) { thermostat in
            switch characteristic.characteristicType {
            case HMCharacteristicTypeCurrentTemperature: thermostat.currentC = value
            case HMCharacteristicTypeTargetTemperature:
                if acceptTarget { thermostat.targetC = value }
            case HMCharacteristicTypeTargetHeatingCooling: thermostat.mode = .init(rawValue: Int(value)) ?? .off
            case HMCharacteristicTypeCurrentHeatingCooling: thermostat.activity = .init(rawValue: Int(value)) ?? .idle
            case HMCharacteristicTypeCurrentRelativeHumidity: thermostat.humidity = value
            case HMCharacteristicTypeHeatingThreshold: if heldTargets[id] == nil { thermostat.heatC = value }
            case HMCharacteristicTypeCoolingThreshold: if heldTargets[id] == nil { thermostat.coolC = value }
            default: break
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Light) -> Void) {
        guard let index = lights.firstIndex(where: { $0.id == id }) else { return }
        change(&lights[index])
    }

    private func updateDevice(_ id: UUID, _ change: (inout Device) -> Void) {
        guard let index = devices.firstIndex(where: { $0.id == id }) else { return }
        change(&devices[index])
    }

    private func updateThermostat(_ id: UUID, _ change: (inout Thermostat) -> Void) {
        guard let index = thermostats.firstIndex(where: { $0.id == id }) else { return }
        change(&thermostats[index])
    }

    private func write(_ value: Any, type: String, to id: UUID) {
        guard let characteristic = services[id]?.characteristic(type) else { return }
        let key = "\(id)|\(type)"
        writesInFlight[key, default: 0] += 1
        Task {
            var failure: Error?
            do { try await characteristic.writeValue(value) } catch { failure = error }
            writesInFlight[key, default: 1] -= 1
            lastWrite[key] = .now
            if failure == nil, thermostats.contains(where: { $0.id == id }) {
                // Some thermostats (ecobee) don't announce their new setting, so check back.
                try? await Task.sleep(for: .seconds(3))
                guard writesInFlight[key, default: 0] == 0 else { return }
                lastWrite[key] = nil
                try? await characteristic.readValue()
                apply(characteristic, to: id)
                return
            }
            guard let failure else { return }
            print("[HomeKit] write \(type) failed:", failure.localizedDescription)
            let name = lights.first { $0.id == id }?.name
                ?? thermostats.first { $0.id == id }?.name
                ?? devices.first { $0.id == id }?.name ?? "A device"
            showWriteError("\(name) didn't respond")
            // Show what the accessory really has instead of a value that didn't stick.
            if writesInFlight[key, default: 0] == 0 {
                lastWrite[key] = nil
                try? await characteristic.readValue()
                apply(characteristic, to: id)
            }
        }
    }

    /// True while our own change to this characteristic is still settling.
    private func isSettling(_ characteristic: HMCharacteristic, id: UUID) -> Bool {
        let key = "\(id)|\(characteristic.characteristicType)"
        if writesInFlight[key, default: 0] > 0 { return true }
        if let last = lastWrite[key], Date.now.timeIntervalSince(last) < 1.5 { return true }
        return false
    }

    private func showWriteError(_ message: String) {
        writeError = message
        errorTask?.cancel()
        errorTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            writeError = nil
        }
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

    // MARK: - Energy

    private static let onSinceKey = "onSince.v1"

    private static func savedOnSince() -> [String: Date] {
        guard let data = UserDefaults.standard.data(forKey: onSinceKey),
              let saved = try? JSONDecoder().decode([String: Date].self, from: data) else { return [:] }
        return saved
    }

    /// Notes when things turn on, and forgets them when they turn off. Unreachable
    /// accessories keep their time, since their state isn't known.
    private func trackOnSince() {
        let now = Date.now
        var updated: [String: Date] = [:]
        let items = lights.map { ($0.key, $0.isOn, $0.isReachable) }
            + devices.filter(\.kind.usesPower).map { ($0.key, $0.active, $0.isReachable) }
        for (key, isOn, isReachable) in items {
            if !isReachable {
                updated[key] = onSince[key]
            } else if isOn {
                updated[key] = onSince[key] ?? now
            }
        }
        guard updated != onSince else { return }
        onSince = updated
        if !isDemo, let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.onSinceKey)
        }
    }

    /// Re-reads power meters, which often don't announce changes on their own.
    func refreshPower() async {
        let types: Set<String> = [EveCharacteristic.watts, EveCharacteristic.kilowattHours]
        for (id, service) in services {
            for characteristic in service.characteristics where types.contains(characteristic.characteristicType) {
                Task {
                    try? await characteristic.readValue()
                    apply(characteristic, to: id)
                }
            }
        }
    }

    // MARK: - Demo data

    private func loadDemo() {
        isDemo = true
        onSince = [:]
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
        roomNames = ["Living Room", "Kitchen", "Bedroom", "Entry", "Garage", "Outside"]
        if let selectedRoom, !roomNames.contains(selectedRoom) { self.selectedRoom = nil }
        devices = [
            Device(id: UUID(), name: "Front Door", roomName: "Entry", kind: .lock, active: true, isReachable: true),
            Device(id: UUID(), name: "Garage", roomName: "Garage", kind: .garage, active: false, isReachable: true),
            Device(id: UUID(), name: "Back Door", roomName: "Kitchen", kind: .contact, active: false, isReachable: true),
            Device(id: UUID(), name: "Shades", roomName: "Living Room", kind: .shade, active: true, level: 100, isReachable: true),
            Device(id: UUID(), name: "Ceiling Fan", roomName: "Bedroom", kind: .fan, active: false, level: 60, isReachable: true),
            Device(id: UUID(), name: "Coffee Maker", roomName: "Kitchen", kind: .outlet, active: false, watts: 0, energyKWh: 41.2, isReachable: true),
            Device(id: UUID(), name: "Space Heater", roomName: "Bedroom", kind: .outlet, active: true, watts: 1480, energyKWh: 212.6, isReachable: true),
            Device(id: UUID(), name: "TV", roomName: "Living Room", kind: .outlet, active: true, watts: 94, energyKWh: 88.3, isReachable: true),
        ]
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
        // Pretend some things have been on a while, so the energy view has something to say.
        onSince["Bedroom|Space Heater"] = .now.addingTimeInterval(-6.2 * 3600)
        onSince["Living Room|TV"] = .now.addingTimeInterval(-50 * 60)
        onSince["Living Room|Ceiling"] = .now.addingTimeInterval(-3 * 3600)
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
            updateDevice(service.uniqueIdentifier) { $0.isReachable = accessory.isReachable }
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
