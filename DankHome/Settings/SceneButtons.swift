//
//  SceneButtons.swift
//  DankHome
//
//  The buttons along the bottom of the dashboard. Until customized they mirror the
//  Home app's scenes; once edited, each can run a Home scene or a custom set of
//  light, thermostat and music changes.
//

import MusicKit
import SwiftUI

struct SceneButton: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var symbol: String
    var action: Action

    enum Action: Codable, Equatable {
        case homeScene(name: String)
        case custom(CustomScene)
    }

    init(id: UUID = UUID(), name: String, symbol: String, action: Action) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.action = action
    }

    init(homeScene scene: HomeScene) {
        self.init(id: scene.id, name: scene.name, symbol: scene.symbol, action: .homeScene(name: scene.name))
    }

    var summary: String {
        switch action {
        case .homeScene(let name):
            return "Home scene: \(name)"
        case .custom(let scene):
            var parts: [String] = []
            if !scene.lights.isEmpty { parts.append(scene.lights.count == 1 ? "1 light" : "\(scene.lights.count) lights") }
            if let devices = scene.devices, !devices.isEmpty {
                parts.append(devices.count == 1 ? "1 device" : "\(devices.count) devices")
            }
            if scene.thermostat != nil { parts.append("thermostat") }
            if scene.music != .none { parts.append("music") }
            return parts.isEmpty ? "Does nothing yet" : parts.joined(separator: " · ")
        }
    }

    static let symbols = [
        "sparkles", "sun.max.fill", "moon.stars.fill", "sofa.fill", "tv.fill", "film", "fork.knife",
        "party.popper.fill", "book.fill", "bed.double.fill", "sunrise.fill", "sunset.fill", "lightbulb.fill",
        "lamp.floor.fill", "flame.fill", "snowflake", "music.note", "gamecontroller.fill", "figure.walk",
        "house.fill", "car.fill", "leaf.fill", "heart.fill", "star.fill", "sailboat.fill", "wineglass.fill",
        "cup.and.saucer.fill", "briefcase.fill", "dumbbell.fill", "power",
    ]
}

/// What a custom button changes. Anything not listed is left alone.
struct CustomScene: Codable, Equatable {
    var lights: [LightSetting] = []
    var thermostat: ThermostatSetting?
    var music: MusicAction = .none
    /// Optional so buttons saved before devices existed still load.
    var devices: [DeviceSetting]?
}

struct DeviceSetting: Codable, Equatable {
    var key: String
    var active: Bool
    /// Shade position or fan speed.
    var level: Double?
}

extension Device {
    var currentSetting: DeviceSetting {
        DeviceSetting(key: key, active: active, level: kind == .shade || kind == .fan ? level : nil)
    }
}

struct LightSetting: Codable, Equatable {
    /// Room and name, which stay stable across launches (unlike demo IDs).
    var key: String
    var on: Bool
    var brightness: Double?
    /// White temperature, or a color — never both.
    var kelvin: Double?
    var hue: Double?
    var saturation: Double?
}

struct ThermostatSetting: Codable, Equatable {
    var mode: Int?
    var targetC: Double?
}

enum MusicAction: String, Codable, CaseIterable, Identifiable {
    case none, play, pause
    var id: Self { self }
    var title: String { ["Don't Change", "Play", "Pause"][Self.allCases.firstIndex(of: self)!] }
}

extension Light {
    var key: String { "\(roomName)|\(name)" }

    /// This light's current state, for "Use Current Lights".
    var currentSetting: LightSetting {
        LightSetting(key: key, on: isOn, brightness: brightness,
                     kelvin: usesWhite ? colorTemperature.map { (1_000_000 / $0).rounded() } : nil,
                     hue: usesWhite ? nil : hue, saturation: usesWhite ? nil : saturation)
    }
}

extension AppSettings {
    /// The buttons to show: the customized list, or the Home app's scenes.
    func sceneButtons(home: HomeStore) -> [SceneButton] {
        prefs.sceneButtons ?? home.scenes.map { SceneButton(homeScene: $0) }
    }

    /// Edits the list, turning the mirrored Home scenes into a customized list on first change.
    func editSceneButtons(home: HomeStore, _ change: (inout [SceneButton]) -> Void) {
        var buttons = sceneButtons(home: home)
        change(&buttons)
        prefs.sceneButtons = buttons
    }
}

/// Runs a scene button against the home and the music player.
struct SceneRunner {
    let home: HomeStore
    let music: MusicStore
    let settings: AppSettings

    func run(_ button: SceneButton) {
        switch button.action {
        case .homeScene(let name):
            if let scene = home.scenes.first(where: { $0.name == name }) { home.run(scene) }
        case .custom(let scene):
            for setting in scene.lights {
                guard let light = home.lights.first(where: { $0.key == setting.key }), light.isReachable else { continue }
                guard setting.on else {
                    home.setPower(false, for: light.id)
                    continue
                }
                if let kelvin = setting.kelvin {
                    home.setWhite(kelvin: kelvin, for: light.id)
                } else if let hue = setting.hue {
                    home.setColor(hue: hue, saturation: setting.saturation ?? 85, for: light.id)
                }
                if let brightness = setting.brightness, light.brightness != nil {
                    home.setBrightness(brightness, for: light.id, commit: true)
                } else {
                    home.setPower(true, for: light.id)
                }
            }
            for setting in scene.devices ?? [] {
                guard let device = home.devices.first(where: { $0.key == setting.key }), device.isReachable else { continue }
                if let level = setting.level, setting.active {
                    home.setLevel(level, for: device.id)
                } else if device.active != setting.active {
                    home.setActive(setting.active, for: device.id)
                }
            }
            if let setting = scene.thermostat, let thermostat = home.thermostats.first {
                if let mode = setting.mode.flatMap(Thermostat.Mode.init(rawValue:)) { home.setMode(mode, for: thermostat.id) }
                if let target = setting.targetC { home.setTarget(target, for: thermostat.id) }
            }
            switch scene.music {
            case .play where music.isAuthorized && music.player.state.playbackStatus != .playing:
                music.togglePlayPause()
            case .pause:
                music.player.pause()
            default:
                break
            }
        }
    }

    /// For the assistant: runs the button (or Home scene) whose name matches.
    func run(named name: String) -> String? {
        let wanted = name.lowercased().replacingOccurrences(of: " ", with: "")
        let buttons = settings.sceneButtons(home: home)
        let match = buttons.first { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == wanted }
            ?? buttons.first { $0.name.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.name) }
        guard let match else { return nil }
        run(match)
        return "Ran \(match.name)."
    }
}

// MARK: - Recording

/// Records a custom button by watching what the person does on the dashboard.
/// At the end it keeps every light, thermostat setting and music change that was
/// touched or differs from when recording started.
@Observable
final class SceneRecorder {
    struct Session {
        var buttonID: UUID
        var name: String
        var startLights: [String: LightSetting]
        var startDevices: [String: DeviceSetting]
        var startThermostat: Thermostat?
        var startPlaying: Bool
    }

    /// The result waiting to be reviewed and saved.
    struct Review: Identifiable {
        var id: UUID { buttonID }
        var buttonID: UUID
        var name: String
        var scene: CustomScene
    }

    private(set) var session: Session?
    var review: Review?
    var isRecording: Bool { session != nil }

    func start(buttonID: UUID, name: String, home: HomeStore, music: MusicStore) {
        session = Session(
            buttonID: buttonID,
            name: name,
            startLights: Dictionary(home.lights.map { ($0.key, $0.currentSetting) }, uniquingKeysWith: { first, _ in first }),
            startDevices: Dictionary(home.devices.map { ($0.key, $0.currentSetting) }, uniquingKeysWith: { first, _ in first }),
            startThermostat: home.thermostats.first,
            startPlaying: music.player.state.playbackStatus == .playing
        )
        home.touched = []
        music.touched = false
    }

    func finish(home: HomeStore, music: MusicStore) {
        guard let session else { return }
        let touched = home.touched ?? []
        var scene = CustomScene()

        for light in home.lights where light.isReachable {
            let final = light.currentSetting
            guard touched.contains(light.id) || session.startLights[light.key] != final else { continue }
            scene.lights.append(final.on ? final : LightSetting(key: light.key, on: false))
        }
        var devices: [DeviceSetting] = []
        for device in home.devices where device.isControllable && device.isReachable {
            let final = device.currentSetting
            if touched.contains(device.id) || session.startDevices[device.key] != final { devices.append(final) }
        }
        if !devices.isEmpty { scene.devices = devices }
        if let thermostat = home.thermostats.first,
           touched.contains(thermostat.id)
            || thermostat.mode != session.startThermostat?.mode
            || thermostat.targetC != session.startThermostat?.targetC {
            scene.thermostat = ThermostatSetting(mode: thermostat.mode.rawValue,
                                                 targetC: thermostat.mode == .off ? nil : thermostat.targetC)
        }
        let playing = music.player.state.playbackStatus == .playing
        if music.touched || playing != session.startPlaying {
            scene.music = playing ? .play : .pause
        }

        review = Review(buttonID: session.buttonID, name: session.name, scene: scene)
        stopTracking(home: home, music: music)
    }

    func cancel(home: HomeStore, music: MusicStore) {
        stopTracking(home: home, music: music)
    }

    private func stopTracking(home: HomeStore, music: MusicStore) {
        home.touched = nil
        music.touched = false
        session = nil
    }
}

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

/// Floating bar shown on the dashboard while recording.
struct RecordingBanner: View {
    @Environment(SceneRecorder.self) private var recorder
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @State private var pulse = false

    var body: some View {
        HStack(spacing: Metrics.inner) {
            Circle()
                .fill(.red)
                .frame(width: 12, height: 12)
                .opacity(pulse ? 0.35 : 1)
                .animation(.easeInOut(duration: 0.8).repeatForever(), value: pulse)
                .onAppear { pulse = true }
            VStack(alignment: .leading, spacing: 1) {
                Text("Recording “\(recorder.session?.name ?? "")”")
                    .font(.subheadline.weight(.semibold))
                Text("Set lights, devices, the thermostat and music how you want them. Hold a light for color.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button("Cancel") { recorder.cancel(home: home, music: music) }
                .buttonStyle(.glass)
            Button {
                recorder.finish(home: home, music: music)
            } label: {
                Text("Done").fontWeight(.semibold)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Metrics.cardPadding)
        .frame(height: Metrics.headerHeight + 18)
        .glassEffect(.regular.tint(.red.opacity(0.25)), in: .capsule)
    }
}

/// "Here's what your button will do" — shown after recording.
struct RecordingReviewView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(SceneRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State var review: SceneRecorder.Review
    @State private var editing: SceneStep?

    var body: some View {
        let steps = SceneStep.steps(for: review.scene, unit: settings.prefs, home: home)
        NavigationStack {
            List {
                Section {
                    if steps.isEmpty {
                        Label("Nothing was changed while recording.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        SceneStepList(steps: steps, onEdit: { editing = $0 }) { SceneStep.remove($0, from: &review.scene) }
                    }
                    AddStepButton(scene: $review.scene) { editing = $0 }
                } header: {
                    Text("When tapped, \(review.name) will")
                } footer: {
                    Text("Tap a step to change it. Swipe left on a step to remove it. Then save.")
                }

                Section {
                    Button {
                        let id = review.buttonID
                        let name = review.name
                        dismiss()
                        recorder.start(buttonID: id, name: name, home: home, music: music)
                    } label: {
                        Label("Record Again", systemImage: "record.circle")
                    }
                }
            }
            .navigationTitle("Review")
            .sheet(item: $editing) { step in
                StepEditor(step: step, scene: $review.scene)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let scene = review.scene
                        settings.editSceneButtons(home: home) { buttons in
                            if let index = buttons.firstIndex(where: { $0.id == review.buttonID }) {
                                buttons[index].action = .custom(scene)
                            }
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(steps.isEmpty)
                }
            }
        }
    }
}

// MARK: - Settings

struct SceneButtonsSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @State private var newButton: UUID?

    var body: some View {
        let buttons = settings.sceneButtons(home: home)
        Form {
            Section {
                ForEach(buttons) { button in
                    NavigationLink {
                        SceneButtonSetup(buttonID: button.id)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(button.name)
                                Text(button.summary).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: button.symbol)
                        }
                    }
                }
                .onDelete { offsets in settings.editSceneButtons(home: home) { $0.remove(atOffsets: offsets) } }
                .onMove { from, to in settings.editSceneButtons(home: home) { $0.move(fromOffsets: from, toOffset: to) } }

                Button {
                    let button = SceneButton(name: "", symbol: "sparkles", action: .custom(CustomScene()))
                    settings.editSceneButtons(home: home) { $0.append(button) }
                    newButton = button.id
                } label: {
                    Label("New Button", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Buttons")
            } footer: {
                Text(settings.prefs.sceneButtons == nil
                     ? "These are your Home app scenes. Tap one to change it, or make a new button."
                     : "Shown along the bottom of the dashboard. Tap Edit to reorder or delete.")
            }

            if settings.prefs.sceneButtons != nil {
                Section {
                    Button("Reset to Home App Scenes", role: .destructive) {
                        settings.prefs.sceneButtons = nil
                    }
                }
            }
        }
        .navigationTitle("Scene Buttons")
        .toolbar { EditButton() }
        .navigationDestination(item: $newButton) { SceneButtonSetup(buttonID: $0) }
    }
}

/// Setting up a button as three short steps: name it, choose how it works, then
/// record it (or pick a Home scene).
struct SceneButtonSetup: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(SceneRecorder.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    let buttonID: UUID
    /// Typed locally so saving each keystroke can't drop letters mid-word.
    @State private var name = ""
    @State private var editingStep: SceneStep?

    private var button: SceneButton? {
        settings.sceneButtons(home: home).first { $0.id == buttonID }
    }

    private func edit(_ change: (inout SceneButton) -> Void) {
        settings.editSceneButtons(home: home) { buttons in
            if let index = buttons.firstIndex(where: { $0.id == buttonID }) { change(&buttons[index]) }
        }
    }

    var body: some View {
        content
            .onAppear { name = button?.name ?? "" }
            .onChange(of: name) { _, newName in
                let trimmed = newName.trimmingCharacters(in: .whitespaces)
                if button?.name != trimmed { edit { $0.name = trimmed } }
            }
    }

    @ViewBuilder private var content: some View {
        if let button {
            Form {
                // 1. Name it
                Section {
                    TextField("Movie Night", text: $name)
                        .font(.title3)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                        ForEach(SceneButton.symbols, id: \.self) { symbol in
                            Button {
                                edit { $0.symbol = symbol }
                            } label: {
                                Image(systemName: symbol)
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(symbol == button.symbol ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06),
                                                in: .rect(cornerRadius: 10))
                                    .overlay(RoundedRectangle(cornerRadius: 10)
                                        .stroke(symbol == button.symbol ? Color.accentColor : .clear, lineWidth: 2))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    StepHeader(number: 1, title: "Name it")
                }

                // 2. How it works
                Section {
                    HStack(spacing: 12) {
                        choiceCard(title: "Record what I do", detail: "Set things up on the dashboard and DankHome remembers.",
                                   symbol: "record.circle", selected: isCustom(button)) {
                            if !isCustom(button) { edit { $0.action = .custom(CustomScene()) } }
                        }
                        choiceCard(title: "Run a Home scene", detail: "Use a scene you made in the Home app.",
                                   symbol: "house.fill", selected: !isCustom(button)) {
                            if isCustom(button) { edit { $0.action = .homeScene(name: home.scenes.first?.name ?? "") } }
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    StepHeader(number: 2, title: "Choose how it works")
                }

                // 3. Record or pick
                switch button.action {
                case .custom(let scene):
                    recordSection(button, scene: scene)
                case .homeScene(let name):
                    Section {
                        ForEach(home.scenes) { scene in
                            Button {
                                edit { $0.action = .homeScene(name: scene.name) }
                            } label: {
                                HStack {
                                    Label(scene.name, systemImage: scene.symbol)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if scene.name == name {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                        if home.scenes.isEmpty {
                            Text("No scenes yet. Make one in the Home app.").foregroundStyle(.secondary)
                        }
                    } header: {
                        StepHeader(number: 3, title: "Pick the scene")
                    }
                }

                Section {
                    Button {
                        Feedback.press()
                        SceneRunner(home: home, music: music, settings: settings).run(button)
                    } label: {
                        Label("Try It Now", systemImage: "play.fill")
                    }
                    .disabled(button.summary == "Does nothing yet")
                    Button("Delete Button", role: .destructive) {
                        settings.editSceneButtons(home: home) { $0.removeAll { $0.id == buttonID } }
                        dismiss()
                    }
                }
            }
            .navigationTitle(button.name.isEmpty ? "New Button" : button.name)
            .sheet(item: $editingStep) { step in
                StepEditor(step: step, scene: customScene)
            }
        }
    }

    /// The button's custom steps, editable.
    private var customScene: Binding<CustomScene> {
        Binding(
            get: {
                if case .custom(let scene) = settings.sceneButtons(home: home).first(where: { $0.id == buttonID })?.action {
                    return scene
                }
                return CustomScene()
            },
            set: { scene in edit { $0.action = .custom(scene) } }
        )
    }

    @ViewBuilder
    private func recordSection(_ button: SceneButton, scene: CustomScene) -> some View {
        let steps = SceneStep.steps(for: scene, unit: settings.prefs, home: home)
        Section {
            if steps.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tap Start Recording, then set your lights, thermostat and music on the dashboard exactly how you want them. Tap Done when you're finished.")
                        .foregroundStyle(.secondary)
                    recordButton(button, title: "Start Recording")
                }
                .padding(.vertical, 6)
                AddStepButton(scene: customScene) { editingStep = $0 }
            } else {
                SceneStepList(steps: steps, onEdit: { editingStep = $0 }) { step in
                    edit {
                        guard case .custom(var scene) = $0.action else { return }
                        SceneStep.remove(step, from: &scene)
                        $0.action = .custom(scene)
                    }
                }
                AddStepButton(scene: customScene) { editingStep = $0 }
                recordButton(button, title: "Record Again")
            }
        } header: {
            StepHeader(number: 3, title: steps.isEmpty ? "Record it" : "When tapped, it will")
        } footer: {
            if !steps.isEmpty { Text("Tap a step to change it. Swipe left on a step to remove it.") }
        }
    }

    private func recordButton(_ button: SceneButton, title: String) -> some View {
        Button {
            if name.isEmpty { name = "New Button" }
            edit { $0.name = name }
            recorder.start(buttonID: button.id, name: name, home: home, music: music)
        } label: {
            Label(title, systemImage: "record.circle.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
    }

    private func isCustom(_ button: SceneButton) -> Bool {
        if case .custom = button.action { true } else { false }
    }

    private func choiceCard(title: String, detail: String, symbol: String, selected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: symbol)
                        .font(.title2)
                        .foregroundStyle(selected ? Color.accentColor : .primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selected ? Color.accentColor : .secondary)
                }
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Selection shows as a soft fill; an outline gets clipped by the list's corners.
            .background(selected ? Color.accentColor.opacity(0.18) : Color(white: 0.17), in: .rect(cornerRadius: 22))
            .contentShape(.rect(cornerRadius: 22))
        }
        .buttonStyle(.plain)
    }
}

/// Numbered step title: ① Name it.
private struct StepHeader: View {
    var number: Int
    var title: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Color.accentColor, in: .circle)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .textCase(nil)
        }
    }
}
