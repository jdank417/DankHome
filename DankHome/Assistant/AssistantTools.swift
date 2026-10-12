//
//  AssistantTools.swift
//  DankHome
//
//  Actions the on-device model can take. Each tool hops to the main actor to
//  touch the stores, and returns a short plain-text result the model can read.
//

import FoundationModels
import MusicKit
import SwiftUI

nonisolated struct ControlLightsTool: Tool {
    let home: HomeStore
    let name = "controlLights"
    let description = "Turns lights on or off, sets brightness, or changes color. Leave room and light empty to affect every light."

    @Generable
    nonisolated enum Power {
        case on, off, unchanged
    }

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "on or off to switch the lights; unchanged when only changing brightness or color")
        var power: Power
        @Guide(description: "Room name such as Kitchen. Empty for every room.")
        var room: String?
        @Guide(description: "A specific light's name. Empty for all lights in the room.")
        var light: String?
        @Guide(description: "Brightness percent from 1 to 100", .range(1...100))
        var brightness: Int?
        @Guide(description: "A color like red, blue, purple, warm white, cool white or daylight")
        var color: String?
    }

    func call(arguments: Arguments) async throws -> String {
        let on: Bool? = switch arguments.power {
        case .on: true
        case .off: false
        case .unchanged: nil
        }
        return await home.assistantControlLights(room: arguments.room, light: arguments.light, on: on,
                                                 brightness: arguments.brightness, color: arguments.color)
    }
}

nonisolated struct DeviceTool: Tool {
    let home: HomeStore
    let name = "controlDevice"
    let description = "Locks a door, closes the garage or shades, opens shades, or turns a fan, outlet or switch on or off."

    @Generable
    nonisolated enum Action {
        case lock, unlock, open, close, on, off
    }

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The device's name, such as Front Door, Garage or Ceiling Fan")
        var device: String
        var action: Action
    }

    func call(arguments: Arguments) async throws -> String {
        let active: Bool = switch arguments.action {
        case .lock, .open, .on: true
        case .unlock, .close, .off: false
        }
        return await home.assistantControlDevice(arguments.device, active: active)
    }
}

nonisolated struct ThermostatTool: Tool {
    let home: HomeStore
    let settings: AppSettings
    let name = "setThermostat"
    let description = "Sets the thermostat's target temperature and/or mode (off, heat, cool, auto)."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Target temperature in the home's units")
        var temperature: Double?
        @Guide(description: "One of: off, heat, cool, auto")
        var mode: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await home.assistantThermostat(temperature: arguments.temperature, mode: arguments.mode,
                                       unit: settings.prefs.temperatureUnit)
    }
}

nonisolated struct SceneTool: Tool {
    let runner: SceneRunner
    let name = "runScene"
    let description = "Runs a scene button by name, such as Movie or Good Night."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The scene's name")
        var scene: String
    }

    func call(arguments: Arguments) async throws -> String {
        await runner.assistantRun(arguments.scene)
    }
}

nonisolated struct MusicTool: Tool {
    let music: MusicStore
    let name = "controlMusic"
    let description = "Controls Apple Music: play, pause, next or previous, or play a library playlist by name."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "One of: play, pause, next, previous")
        var action: String?
        @Guide(description: "Name of a playlist to play")
        var playlist: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await music.assistantControl(action: arguments.action, playlist: arguments.playlist)
    }
}

nonisolated struct TimerTool: Tool {
    let automation: AutomationStore
    let name = "setTimer"
    let description = "Does something later: after a number of minutes, carries out a command such as turn off the kitchen lights."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "What to do when the time is up, as a short command, such as turn off the kitchen lights")
        var command: String
        @Guide(description: "Minutes from now. One hour is 60.", .range(1...1440))
        var minutes: Int
    }

    func call(arguments: Arguments) async throws -> String {
        await automation.assistantTimer(arguments.command, minutes: arguments.minutes)
    }
}

nonisolated struct RoutineTool: Tool {
    let automation: AutomationStore
    let name = "scheduleRoutine"
    let description = "Repeats a command on a schedule, such as every night at 10 PM run Good Night, or weekdays at sunset close the shades."

    @Generable
    nonisolated enum When {
        case clockTime, sunrise, sunset
    }

    @Generable
    nonisolated enum Days {
        case everyDay, weekdays, weekends
    }

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "What to do each time, as a short command, such as run Good Night or close the shades")
        var command: String
        @Guide(description: "clockTime for a time of day, or sunrise or sunset")
        var when: When
        @Guide(description: "For clockTime: hour from 0 to 23, so 10 PM is 22", .range(0...23))
        var hour: Int?
        @Guide(description: "For clockTime: minute from 0 to 59", .range(0...59))
        var minute: Int?
        var days: Days
    }

    func call(arguments: Arguments) async throws -> String {
        let time: RoutineTime = switch arguments.when {
        case .clockTime: .clock(hour: arguments.hour ?? 22, minute: arguments.minute ?? 0)
        case .sunrise: .sunrise(offsetMinutes: 0)
        case .sunset: .sunset(offsetMinutes: 0)
        }
        let days: Set<Int> = switch arguments.days {
        case .everyDay: []
        case .weekdays: Routine.weekdays
        case .weekends: Routine.weekends
        }
        return await automation.assistantRoutine(arguments.command, time: time, days: days)
    }
}

nonisolated struct HomeStatusTool: Tool {
    let home: HomeStore
    let weather: WeatherStore
    let settings: AppSettings
    let automation: AutomationStore
    let name = "getHomeStatus"
    let description = "Returns the current state of every light, the thermostat, scenes, the weather and what's playing."

    @Generable
    nonisolated struct Arguments {}

    func call(arguments: Arguments) async throws -> String {
        let status = await home.assistantStatus(weather: weather, prefs: settings.prefs)
        guard let scheduled = await automation.assistantSummary else { return status }
        return status + "\n" + scheduled
    }
}

// MARK: - Store helpers

extension HomeStore {
    func assistantControlLights(room: String?, light: String?, on: Bool?, brightness: Int?, color: String?) -> String {
        // The model is loose with names ("living room" as a light, "lamp" as a room),
        // so match generously: a filter that matches nothing is ignored when the other one hits.
        func meaningful(_ value: String?, ignoring: [String]) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty,
                  !ignoring.contains(value.lowercased()) else { return nil }
            return value
        }
        let room = meaningful(room, ignoring: ["all", "home", "house", "everywhere", "every room", "all rooms"])
        let light = meaningful(light, ignoring: ["all", "lights", "all lights", "light"])
        let byRoom = room.map { room in lights.filter { $0.roomName.fuzzyMatches(room) || $0.name.fuzzyMatches(room) } }
        var targets = (byRoom?.isEmpty == false ? byRoom : nil) ?? lights
        if let light {
            let byName = targets.filter { $0.name.fuzzyMatches(light) || $0.roomName.fuzzyMatches(light) }
            if !byName.isEmpty {
                targets = byName
            } else if byRoom?.isEmpty != false {
                targets = []
            }
        } else if byRoom?.isEmpty == true {
            targets = []
        }
        guard on != nil || brightness != nil || color != nil else {
            return "Nothing changed: set power to on or off, or give a brightness or color."
        }
        guard !targets.isEmpty else {
            return "No lights matched. Rooms: \(roomNames.joined(separator: ", ")). Lights: \(lights.map(\.name).joined(separator: ", "))."
        }

        for target in targets where target.isReachable {
            if on == false {
                setPower(false, for: target.id)
                continue
            }
            if let color { applyColor(color, to: target) }
            if let brightness {
                setBrightness(Double(brightness), for: target.id, commit: true)
            } else if on == true || color != nil {
                setPower(true, for: target.id)
            }
        }
        let changed = targets.filter(\.isReachable)
        let verb = on == false ? "Turned off" : (on == true && brightness == nil && color == nil ? "Turned on" : "Adjusted")
        let names = changed.count > 3 ? "\(changed.count) lights" : changed.map(\.name).formatted(.list(type: .and))
        let offline = targets.filter { !$0.isReachable }.map(\.name)
        var result = changed.isEmpty ? "No lights could be changed." : "Success. \(verb) \(names)."
        if !offline.isEmpty {
            result += " \(offline.formatted(.list(type: .and))) \(offline.count == 1 ? "is" : "are") offline and skipped."
        }
        return result
    }

    private func applyColor(_ name: String, to light: Light) {
        let name = name.lowercased()
        let whites: [(String, Double)] = [("daylight", 6500), ("cool", 5000), ("bright white", 4000), ("soft", 2700),
                                          ("warm", 2700), ("candle", 2200), ("white", 3000)]
        if let kelvin = whites.first(where: { name.contains($0.0) })?.1 {
            setWhite(kelvin: kelvin, for: light.id)
            return
        }
        let hues: [(String, Double)] = [("red", 0), ("orange", 25), ("amber", 35), ("yellow", 52), ("green", 120),
                                        ("teal", 175), ("cyan", 190), ("blue", 225), ("indigo", 250), ("purple", 275),
                                        ("violet", 275), ("magenta", 300), ("pink", 330)]
        if let hue = hues.first(where: { name.contains($0.0) })?.1, light.supportsColor {
            setColor(hue: hue, saturation: 90, for: light.id)
        }
    }

    func assistantControlDevice(_ name: String, active: Bool) -> String {
        guard let device = devices.first(where: { $0.name.fuzzyMatches(name) })
                ?? devices.first(where: { "\($0.roomName) \($0.name)".fuzzyMatches(name) }) else {
            return "No device called \(name). Devices: \(devices.map(\.name).joined(separator: ", "))."
        }
        guard device.isControllable else { return "\(device.name) is a sensor; it's \(device.status.lowercased())." }
        guard device.isReachable else { return "\(device.name) isn't responding." }
        // Safety: unlocking doors and opening the garage happen on the dashboard only.
        if (device.kind == .lock && !active) || (device.kind == .garage && active) {
            return "For safety, \(device.kind == .lock ? "unlock" : "open") \(device.name) on the dashboard."
        }
        setActive(active, for: device.id)
        let verb = switch device.kind {
        case .lock: "Locked"
        case .garage, .shade: active ? "Opened" : "Closed"
        default: active ? "Turned on" : "Turned off"
        }
        return "Success. \(verb) \(device.name)."
    }

    func assistantThermostat(temperature: Double?, mode: String?, unit: TemperatureUnit) -> String {
        guard let thermostat = thermostats.first else { return "There's no thermostat in this home." }
        if let mode = mode?.lowercased(),
           let match = Thermostat.Mode.allCases.first(where: { mode.contains($0.title.lowercased()) }) {
            setMode(match, for: thermostat.id)
        } else if temperature != nil, thermostat.mode == .off {
            setMode(.auto, for: thermostat.id)
        }
        if let temperature {
            let celsius = unit == .fahrenheit ? (temperature - 32) * 5 / 9 : temperature
            setTarget(celsius, for: thermostat.id)
        }
        let updated = thermostats.first { $0.id == thermostat.id } ?? thermostat
        let target = unit == .fahrenheit ? updated.targetC * 9 / 5 + 32 : updated.targetC
        return "Thermostat is \(updated.mode.title.lowercased()), set to \(Int(target.rounded()))\(unit.symbol)."
    }

    func assistantRunScene(_ name: String) -> String {
        guard let scene = scenes.first(where: { $0.name.fuzzyMatches(name) }) else {
            return "No scene called \(name). Scenes: \(scenes.map(\.name).joined(separator: ", "))."
        }
        run(scene)
        return "Ran the \(scene.name) scene."
    }

    func assistantStatus(weather: WeatherStore, prefs: Preferences) -> String {
        var lines: [String] = []
        // Outdoor weather first and clearly labeled, so it isn't mistaken for a room.
        if let current = weather.current {
            let place = weather.placeName.isEmpty ? "" : " in \(weather.placeName)"
            lines.append("OUTDOOR WEATHER\(place): now \(prefs.formatTemperature(celsius: current.temperature)) and \(WeatherCode.description(current.code).lowercased()); today's high \(prefs.formatTemperature(celsius: current.high)), low \(prefs.formatTemperature(celsius: current.low)).")
            let upcoming = weather.hours.prefix(8).map {
                "\($0.id.formatted(.dateTime.hour())) \(prefs.formatTemperature(celsius: $0.temperature)) \(WeatherCode.description($0.code).lowercased())"
            }
            lines.append("OUTDOOR FORECAST: \(upcoming.joined(separator: "; ")).")
        }
        for thermostat in thermostats {
            lines.append("INDOOR THERMOSTAT: \(thermostat.mode.title.lowercased()), set to \(prefs.formatTemperature(celsius: thermostat.targetC)), indoor temperature \(prefs.formatTemperature(celsius: thermostat.currentC)).")
        }
        var lightLines: [String] = []
        for room in roomNames {
            let inRoom = lights.filter { $0.roomName == room }
            guard !inRoom.isEmpty else { continue }
            let described = inRoom.map { light in
                guard light.isReachable else { return "\(light.name) not responding" }
                guard light.isOn else { return "\(light.name) off" }
                return "\(light.name) on\(light.brightness.map { " \(Int($0))%" } ?? "")"
            }
            lightLines.append("\(room): \(described.joined(separator: ", "))")
        }
        if !lightLines.isEmpty { lines.append("LIGHTS: " + lightLines.joined(separator: ". ") + ".") }
        if !devices.isEmpty {
            lines.append("DEVICES: " + devices.map { "\($0.name) (\($0.roomName)) \($0.status.lowercased())" }.joined(separator: ", ") + ".")
        }
        let powered = poweredItems().filter { $0.source != .light }
        if !powered.isEmpty {
            let described = powered.map { item in
                var text = item.name
                if let since = item.since { text += " on for \(EnergyFormat.duration(Date.now.timeIntervalSince(since)))" }
                if let watts = item.watts { text += " using \(EnergyFormat.watts(watts))" }
                return text
            }
            lines.append("POWER: \(described.joined(separator: ", "))\(totalWatts.map { "; total \(EnergyFormat.watts($0))" } ?? "").")
        }
        let sceneNames = (prefs.sceneButtons?.map(\.name) ?? []) + scenes.map(\.name)
        if !sceneNames.isEmpty { lines.append("SCENES: \(Array(Set(sceneNames)).sorted().joined(separator: ", ")).") }
        if let entry = SystemMusicPlayer.shared.queue.currentEntry {
            let status = SystemMusicPlayer.shared.state.playbackStatus == .playing ? "playing" : "paused"
            lines.append("MUSIC: \(status) \(entry.title)\(entry.subtitle.map { " by \($0)" } ?? "").")
        }
        return lines.joined(separator: "\n")
    }
}

extension AutomationStore {
    func assistantTimer(_ command: String, minutes: Int) -> String {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "Say what to do when the timer ends." }
        let timer = addTimer(command, after: TimeInterval(minutes * 60))
        return "Success. Will \(command.lowercased()) at \(timer.fireDate.formatted(date: .omitted, time: .shortened))."
    }

    func assistantRoutine(_ command: String, time: RoutineTime, days: Set<Int>) -> String {
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return "Say what the routine should do." }
        let routine = Routine(command: command, time: time, days: days)
        save(routine)
        return "Success. \(routine.scheduleText), DankHome will \(command.lowercased())."
    }

    /// Timers and routines, for the home status.
    var assistantSummary: String? {
        var parts = timers.map { "timer: \($0.command) at \($0.fireDate.formatted(date: .omitted, time: .shortened))" }
        parts += routines.filter(\.isEnabled).map { "routine: \($0.command), \($0.scheduleText.lowercased())" }
        return parts.isEmpty ? nil : "SCHEDULED: \(parts.joined(separator: "; "))."
    }
}

extension SceneRunner {
    func assistantRun(_ name: String) -> String {
        run(named: name) ?? home.assistantRunScene(name)
    }
}

extension MusicStore {
    func assistantControl(action: String?, playlist: String?) async -> String {
        if let playlist, !playlist.isEmpty {
            if playlists.isEmpty { await loadPlaylists() }
            guard let match = playlists.first(where: { $0.name.fuzzyMatches(playlist) }) else {
                return "No playlist called \(playlist). Some playlists: \(playlists.prefix(8).map(\.name).joined(separator: ", "))."
            }
            play(match)
            return "Playing \(match.name)."
        }
        switch action?.lowercased() ?? "play" {
        case let a where a.contains("pause") || a.contains("stop"):
            player.pause()
            return "Paused."
        case let a where a.contains("next") || a.contains("skip"):
            next()
            return "Skipped."
        case let a where a.contains("prev") || a.contains("back"):
            previous()
            return "Went back."
        default:
            if player.state.playbackStatus != .playing { togglePlayPause() }
            return "Playing."
        }
    }
}

private extension String {
    /// Loose match either way round, ignoring case: "kitchen" ↔ "Kitchen Lights".
    func fuzzyMatches(_ other: String) -> Bool {
        localizedCaseInsensitiveContains(other) || other.localizedCaseInsensitiveContains(self)
    }
}
