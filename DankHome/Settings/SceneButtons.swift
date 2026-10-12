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
