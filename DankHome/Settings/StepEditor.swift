//
//  StepEditor.swift
//  DankHome
//
//  Edit one recorded step of a custom scene button: a light's power, brightness and
//  color; a device's state; the thermostat's mode and temperature; or music.
//

import SwiftUI

struct StepEditor: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    var step: SceneStep
    @Binding var scene: CustomScene

    var body: some View {
        NavigationStack {
            Form {
                switch step.kind {
                case .light(let key): lightEditor(key)
                case .device(let key): deviceEditor(key)
                case .thermostat: thermostatEditor
                case .music: musicEditor
                }
                Section {
                    Button("Remove Step", role: .destructive) {
                        SceneStep.remove(step, from: &scene)
                        dismiss()
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var title: String {
        switch step.kind {
        case .light(let key), .device(let key): key.split(separator: "|").last.map(String.init) ?? "Step"
        case .thermostat: "Thermostat"
        case .music: "Music"
        }
    }

    // MARK: - Light

    @ViewBuilder
    private func lightEditor(_ key: String) -> some View {
        let light = home.lights.first { $0.key == key }
        if let index = scene.lights.firstIndex(where: { $0.key == key }) {
            let setting = $scene.lights[index]
            Section {
                Toggle("On", isOn: Binding(get: { setting.wrappedValue.on }, set: { on in
                    setting.wrappedValue.on = on
                    if on, setting.wrappedValue.brightness == nil, light?.brightness != nil {
                        setting.wrappedValue.brightness = 100
                    }
                }))
            } footer: {
                if light == nil { Text("This light isn't in your home right now.") }
            }

            if setting.wrappedValue.on, let light {
                if light.brightness != nil {
                    Section("Brightness") {
                        HStack {
                            Image(systemName: "sun.min").foregroundStyle(.secondary)
                            Slider(value: Binding(get: { setting.wrappedValue.brightness ?? 100 },
                                                  set: { setting.wrappedValue.brightness = $0.rounded() }),
                                   in: 1...100)
                            Text("\(Int(setting.wrappedValue.brightness ?? 100))%")
                                .monospacedDigit()
                                .frame(width: 48, alignment: .trailing)
                        }
                    }
                }
                if light.colorTemperature != nil || light.supportsColor {
                    Section("White") {
                        HStack(spacing: 14) {
                            swatch(.secondary.opacity(0.3), symbol: "circle.slash",
                                   selected: setting.wrappedValue.kelvin == nil && setting.wrappedValue.hue == nil) {
                                setting.wrappedValue.kelvin = nil
                                setting.wrappedValue.hue = nil
                                setting.wrappedValue.saturation = nil
                            }
                            ForEach([2200.0, 2700, 3000, 4000, 5000, 6500], id: \.self) { kelvin in
                                swatch(Light.white(kelvin: kelvin), selected: setting.wrappedValue.kelvin == kelvin) {
                                    setting.wrappedValue.kelvin = kelvin
                                    setting.wrappedValue.hue = nil
                                    setting.wrappedValue.saturation = nil
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                if light.supportsColor {
                    Section("Color") {
                        ColorWheel(hue: setting.wrappedValue.hue ?? 0,
                                   saturation: setting.wrappedValue.saturation ?? 0,
                                   showsThumb: setting.wrappedValue.hue != nil) { hue, saturation in
                            setting.wrappedValue.hue = hue
                            setting.wrappedValue.saturation = saturation
                            setting.wrappedValue.kelvin = nil
                        }
                        .frame(width: 260, height: 260)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private func swatch(_ color: Color, symbol: String? = nil, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 36, height: 36)
                .overlay { if let symbol { Image(systemName: symbol).font(.caption).foregroundStyle(.secondary) } }
                .overlay(Circle().stroke(.white, lineWidth: selected ? 3 : 0).padding(-4))
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Device

    @ViewBuilder
    private func deviceEditor(_ key: String) -> some View {
        let device = home.devices.first { $0.key == key }
        if let index = scene.devices?.firstIndex(where: { $0.key == key }) {
            let setting = Binding(get: { scene.devices?[index] ?? DeviceSetting(key: key, active: false) },
                                  set: { scene.devices?[index] = $0 })
            Section {
                Picker(selection: Binding(get: { setting.wrappedValue.active }, set: { active in
                    setting.wrappedValue.active = active
                    if device?.kind == .shade { setting.wrappedValue.level = active ? 100 : 0 }
                })) {
                    Text(labels(device?.kind).on).tag(true)
                    Text(labels(device?.kind).off).tag(false)
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
            }
            if let kind = device?.kind, kind == .shade || kind == .fan, setting.wrappedValue.active {
                Section(kind == .shade ? "Position" : "Speed") {
                    HStack {
                        Slider(value: Binding(get: { setting.wrappedValue.level ?? 100 },
                                              set: { setting.wrappedValue.level = $0.rounded() }),
                               in: 1...100)
                        Text("\(Int(setting.wrappedValue.level ?? 100))%")
                            .monospacedDigit()
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func labels(_ kind: Device.Kind?) -> (on: String, off: String) {
        switch kind {
        case .lock: ("Lock", "Unlock")
        case .garage, .shade: ("Open", "Close")
        default: ("On", "Off")
        }
    }

    // MARK: - Thermostat

    @ViewBuilder
    private var thermostatEditor: some View {
        if let current = scene.thermostat {
            let thermostat = home.thermostats.first
            let mode = current.mode.flatMap(Thermostat.Mode.init(rawValue:)) ?? .auto
            Section("Mode") {
                Picker("Mode", selection: Binding(get: { mode }, set: { new in
                    scene.thermostat?.mode = new.rawValue
                    if new != .off, scene.thermostat?.targetC == nil {
                        scene.thermostat?.targetC = thermostat?.targetC ?? 21
                    }
                })) {
                    ForEach(Thermostat.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            if mode != .off {
                let target = current.targetC ?? thermostat?.targetC ?? 21
                Section("Temperature") {
                    Stepper {
                        Text(settings.prefs.formatTemperature(celsius: target))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                    } onIncrement: {
                        scene.thermostat?.targetC = nudged(target, by: 1, thermostat: thermostat)
                    } onDecrement: {
                        scene.thermostat?.targetC = nudged(target, by: -1, thermostat: thermostat)
                    }
                }
            }
        }
    }

    /// One displayed degree, in the person's units.
    private func nudged(_ celsius: Double, by degrees: Int, thermostat: Thermostat?) -> Double {
        let range = (thermostat?.minC ?? 10)...(thermostat?.maxC ?? 32)
        switch settings.prefs.temperatureUnit {
        case .fahrenheit:
            let f = (celsius * 9 / 5 + 32).rounded() + Double(degrees)
            return ((((f - 32) * 5 / 9) * 10).rounded() / 10).clamped(to: range)
        case .celsius:
            return (celsius + Double(degrees) * 0.5).clamped(to: range)
        }
    }

    // MARK: - Music

    private var musicEditor: some View {
        Section {
            Picker(selection: $scene.music) {
                Text("Play").tag(MusicAction.play)
                Text("Pause").tag(MusicAction.pause)
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
        }
    }
}
