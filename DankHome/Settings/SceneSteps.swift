//
//  SceneSteps.swift
//  DankHome
//

import SwiftUI

/// One line of "When tapped, this button will…".
struct SceneStep: Identifiable {
    enum Kind { case light(String), device(String), thermostat, music }
    var kind: Kind
    var symbol: String
    var color: Color
    var title: String
    var detail: String?

    var id: String {
        switch kind {
        case .light(let key): "light-\(key)"
        case .device(let key): "device-\(key)"
        case .thermostat: "thermostat"
        case .music: "music"
        }
    }

    static func steps(for scene: CustomScene, unit: Preferences, home: HomeStore? = nil) -> [SceneStep] {
        var steps: [SceneStep] = []
        for light in scene.lights {
            let parts = light.key.split(separator: "|", maxSplits: 1).map(String.init)
            let name = parts.last ?? light.key
            let room = parts.count > 1 ? parts[0] : nil
            guard light.on else {
                steps.append(SceneStep(kind: .light(light.key), symbol: "lightbulb.slash", color: .gray,
                                       title: "Turn off \(name)", detail: room))
                continue
            }
            var details: [String] = []
            if let kelvin = light.kelvin { details.append(whiteName(kelvin)) }
            if let hue = light.hue { details.append(colorName(hue)) }
            if let brightness = light.brightness { details.append("\(Int(brightness))%") }
            if let room { details.append(room) }
            let tint: Color = if let hue = light.hue { Color(hue: hue / 360, saturation: 0.85, brightness: 1) }
                else { Light.white(kelvin: light.kelvin ?? 2700) }
            steps.append(SceneStep(kind: .light(light.key), symbol: "lightbulb.fill", color: tint,
                                   title: "Turn on \(name)", detail: details.joined(separator: " · ")))
        }
        for setting in scene.devices ?? [] {
            let parts = setting.key.split(separator: "|", maxSplits: 1).map(String.init)
            let name = parts.last ?? setting.key
            let kind = home?.devices.first { $0.key == setting.key }?.kind
            let title: String
            var detail = parts.count > 1 ? parts[0] : nil
            switch kind {
            case .lock: title = setting.active ? "Lock \(name)" : "Unlock \(name)"
            case .garage: title = setting.active ? "Open \(name)" : "Close \(name)"
            case .shade:
                if let level = setting.level, level > 0, level < 100 {
                    title = "Set \(name) to \(Int(level))% open"
                } else {
                    title = setting.active ? "Open \(name)" : "Close \(name)"
                }
            case .fan:
                title = setting.active ? "Turn on \(name)" : "Turn off \(name)"
                if setting.active, let level = setting.level { detail = ["\(Int(level))%", detail].compactMap { $0 }.joined(separator: " · ") }
            default: title = setting.active ? "Turn on \(name)" : "Turn off \(name)"
            }
            let symbol = switch kind {
            case .lock: setting.active ? "lock.fill" : "lock.open.fill"
            case .garage: "door.garage.closed"
            case .shade: "blinds.horizontal.closed"
            case .fan: "fan.fill"
            default: "poweroutlet.type.b.fill"
            }
            steps.append(SceneStep(kind: .device(setting.key), symbol: symbol, color: setting.active ? .green : .gray,
                                   title: title, detail: detail))
        }
        if let thermostat = scene.thermostat {
            let mode = thermostat.mode.flatMap(Thermostat.Mode.init(rawValue:)) ?? .auto
            if mode == .off {
                steps.append(SceneStep(kind: .thermostat, symbol: "thermometer.medium", color: .gray,
                                       title: "Turn the thermostat off"))
            } else {
                steps.append(SceneStep(kind: .thermostat, symbol: mode.symbol, color: mode == .cool ? .cyan : .orange,
                                       title: "Set the thermostat to \(unit.formatTemperature(celsius: thermostat.targetC))",
                                       detail: mode.title))
            }
        }
        switch scene.music {
        case .play: steps.append(SceneStep(kind: .music, symbol: "play.fill", color: .pink, title: "Play music"))
        case .pause: steps.append(SceneStep(kind: .music, symbol: "pause.fill", color: .pink, title: "Pause music"))
        case .none: break
        }
        return steps
    }

    static func remove(_ step: SceneStep, from scene: inout CustomScene) {
        switch step.kind {
        case .light(let key): scene.lights.removeAll { $0.key == key }
        case .device(let key):
            scene.devices?.removeAll { $0.key == key }
            if scene.devices?.isEmpty == true { scene.devices = nil }
        case .thermostat: scene.thermostat = nil
        case .music: scene.music = .none
        }
    }

    private static func whiteName(_ kelvin: Double) -> String {
        switch kelvin {
        case ..<2500: "Candlelight"
        case ..<3300: "Warm white"
        case ..<4500: "Neutral white"
        case ..<5800: "Cool white"
        default: "Daylight"
        }
    }

    private static func colorName(_ hue: Double) -> String {
        let names: [(Double, String)] = [(15, "Red"), (40, "Orange"), (65, "Yellow"), (150, "Green"), (200, "Teal"),
                                         (245, "Blue"), (290, "Purple"), (340, "Pink"), (361, "Red")]
        return names.first { hue < $0.0 }?.1 ?? "Color"
    }
}

/// The steps as a list, each removable.
struct SceneStepList: View {
    var steps: [SceneStep]
    var onEdit: (SceneStep) -> Void
    var onRemove: (SceneStep) -> Void

    var body: some View {
        ForEach(steps) { step in
            Button {
                onEdit(step)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: step.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(step.color)
                        .frame(width: 34, height: 34)
                        .background(step.color.opacity(0.18), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title).foregroundStyle(.primary)
                        if let detail = step.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            // Deleting takes a deliberate swipe, so it can't be hit by accident.
            .swipeActions(edge: .trailing) {
                Button("Remove", role: .destructive) {
                    withAnimation { onRemove(step) }
                }
            }
            .accessibilityHint("Edit this step")
        }
    }
}

/// "Add Step": pick a light, device, the thermostat or music that isn't in the scene yet.
struct AddStepButton: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Binding var scene: CustomScene
    /// Called with the new step so its editor can open.
    var onAdded: (SceneStep) -> Void

    private var lights: [Light] {
        home.lights.filter { light in !scene.lights.contains { $0.key == light.key } }
    }
    private var devices: [Device] {
        home.devices.filter { device in device.isControllable && !(scene.devices ?? []).contains { $0.key == device.key } }
    }

    var body: some View {
        Menu {
            if !lights.isEmpty {
                Menu {
                    ForEach(lights) { light in
                        Button("\(light.name) · \(light.roomName)") {
                            var setting = light.currentSetting
                            if !setting.on {
                                setting = LightSetting(key: light.key, on: true, brightness: light.brightness.map { _ in 100 })
                            }
                            scene.lights.append(setting)
                            added("light-\(light.key)")
                        }
                    }
                } label: { Label("Light", systemImage: "lightbulb.fill") }
            }
            if !devices.isEmpty {
                Menu {
                    ForEach(devices) { device in
                        Button("\(device.name) · \(device.roomName)") {
                            scene.devices = (scene.devices ?? []) + [device.currentSetting]
                            added("device-\(device.key)")
                        }
                    }
                } label: { Label("Lock, Door or Device", systemImage: "lock.fill") }
            }
            if scene.thermostat == nil, let thermostat = home.thermostats.first {
                Button {
                    scene.thermostat = ThermostatSetting(mode: thermostat.mode.rawValue,
                                                         targetC: thermostat.mode == .off ? nil : thermostat.targetC)
                    added("thermostat")
                } label: { Label("Thermostat", systemImage: "thermometer.medium") }
            }
            if scene.music == .none {
                Button {
                    scene.music = .play
                    added("music")
                } label: { Label("Music", systemImage: "music.note") }
            }
        } label: {
            Label("Add Step", systemImage: "plus.circle.fill")
        }
    }

    private func added(_ id: String) {
        Feedback.tap()
        // Open the editor for what was just added, once the menu has closed.
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            if let step = SceneStep.steps(for: scene, unit: settings.prefs, home: home).first(where: { $0.id == id }) {
                onAdded(step)
            }
        }
    }
}
