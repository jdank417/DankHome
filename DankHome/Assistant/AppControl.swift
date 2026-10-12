//
//  AppControl.swift
//  DankHome
//
//  Everything in the app the assistant can change besides the devices themselves:
//  the look, the clock, what the dashboard shows, the night clock, the wake-up
//  light, adaptive lighting, saving scenes, managing timers and routines, and
//  opening screens. Each method makes the change and returns a short sentence
//  about it, which both the instant commands and the model's tools use.
//

import SwiftUI

/// Screens the assistant can open. The dashboards watch `request` and present it.
@Observable
final class AppNavigator {
    enum Screen: String, Identifiable {
        case whatsOn, settings, automations
        var id: Self { self }
    }

    var request: Screen?
}

final class AppControl {
    let home: HomeStore
    let settings: AppSettings
    let automation: AutomationStore
    let idle: IdleMonitor
    let navigator: AppNavigator

    init(home: HomeStore, settings: AppSettings, automation: AutomationStore, idle: IdleMonitor, navigator: AppNavigator) {
        self.home = home
        self.settings = settings
        self.automation = automation
        self.idle = idle
        self.navigator = navigator
    }

    // MARK: - Look

    static let colors: [(name: String, color: RGBAColor)] = [
        ("white", .init(.white)), ("warm", .init(Color(red: 1, green: 0.55, blue: 0.35))),
        ("amber", .init(Color(red: 1, green: 0.55, blue: 0.35))), ("orange", .init(.orange)),
        ("yellow", .init(.yellow)), ("mint", .init(.mint)), ("green", .init(.green)), ("teal", .init(.teal)),
        ("cyan", .init(.cyan)), ("blue", .init(.blue)), ("indigo", .init(.indigo)), ("purple", .init(.purple)),
        ("pink", .init(.pink)), ("red", .init(.red)), ("gray", .init(.gray)), ("grey", .init(.gray)),
    ]

    static func color(named name: String) -> RGBAColor? {
        let name = name.lowercased()
        return colors.first { name.contains($0.name) }?.color
    }

    static func theme(named name: String) -> BackgroundTheme? {
        let name = name.lowercased()
        if name.contains("dark") { return .black }
        return BackgroundTheme.allCases.first { name.contains($0.rawValue) || name.contains($0.title.lowercased()) }
    }

    func changeLook(theme: String?, accent: String?, appFont: String?, clockFont: String?, clockColor: String?,
                    weatherEffects: Bool?) -> String {
        var done: [String] = []
        var missed: [String] = []
        if let theme {
            if let match = Self.theme(named: theme) {
                settings.prefs.theme = match
                done.append("the background to \(match.title)")
            } else { missed.append("background “\(theme)”") }
        }
        if let accent {
            if let color = Self.color(named: accent) {
                settings.prefs.accent = color
                done.append("the accent color to \(accent.lowercased())")
            } else { missed.append("color “\(accent)”") }
        }
        if let appFont {
            let name = appFont.lowercased()
            if let font = AppFont.allCases.first(where: { name.contains($0.rawValue) || name.contains($0.title.lowercased()) }) {
                settings.prefs.appFont = font
                done.append("the app font to \(font.title)")
            } else { missed.append("font “\(appFont)”") }
        }
        if let clockFont {
            let name = clockFont.lowercased()
            if let font = ClockFont.allCases.first(where: { name.contains($0.rawValue) || name.contains($0.title.lowercased()) }) {
                settings.prefs.clock.font = font
                done.append("the clock font to \(font.title)")
            } else { missed.append("clock font “\(clockFont)”") }
        }
        if let clockColor {
            if let color = Self.color(named: clockColor) {
                settings.prefs.clock.color = color
                done.append("the clock color to \(clockColor.lowercased())")
            } else { missed.append("color “\(clockColor)”") }
        }
        if let weatherEffects {
            settings.prefs.weatherEffects = weatherEffects
            done.append("animated weather \(weatherEffects ? "on" : "off")")
        }
        var reply = done.isEmpty ? "" : "Changed \(done.formatted(.list(type: .and)))."
        if !missed.isEmpty {
            reply += (reply.isEmpty ? "" : " ") + "Couldn't find \(missed.formatted(.list(type: .and))). "
                + "Backgrounds: \(BackgroundTheme.allCases.map(\.title).joined(separator: ", ")). "
                + "Colors: \(Self.colors.map(\.name).joined(separator: ", "))."
        }
        return reply.isEmpty ? "Nothing to change." : reply
    }

    // MARK: - Dashboard

    func changeDashboard(section: String?, show: Bool?, room: String?, units: String?, clickSounds: Bool?,
                         twentyFourHour: Bool?) -> String {
        var done: [String] = []
        if let section, let show {
            let name = section.lowercased()
            let sections: [(words: [String], path: WritableKeyPath<Preferences, Bool>, title: String)] = [
                (["thermostat", "climate", "temperature"], \.showClimate, "the thermostat"),
                (["weather", "forecast"], \.showWeather, "the weather"),
                (["music", "playing", "song"], \.showMusic, "now playing"),
                (["device", "lock", "door"], \.showDevices, "devices"),
                (["scene", "button"], \.showScenes, "scenes"),
                (["date"], \.showDate, "the date"),
            ]
            guard let match = sections.first(where: { entry in entry.words.contains { name.contains($0) } }) else {
                return "There's no \(section) section. Sections: thermostat, weather, music, devices, scenes and the date."
            }
            settings.prefs[keyPath: match.path] = show
            done.append("\(show ? "showing" : "hiding") \(match.title)")
        }
        if let room {
            let name = room.lowercased()
            if ["all", "all rooms", "every room", "everything", "home", "house", "whole house"].contains(name) {
                home.selectedRoom = nil
                done.append("showing all rooms")
            } else if let match = home.roomNames.first(where: { $0.lowercased() == name })
                        ?? home.roomNames.first(where: { $0.lowercased().contains(name) || name.contains($0.lowercased()) }) {
                home.selectedRoom = match
                done.append("showing the \(match)")
            } else {
                return "There's no room called \(room). Rooms: \(home.roomNames.joined(separator: ", "))."
            }
        }
        if let units {
            let name = units.lowercased()
            let unit: TemperatureUnit = name.hasPrefix("c") || name.contains("metric") ? .celsius : .fahrenheit
            settings.prefs.temperatureUnit = unit
            done.append("temperatures in \(unit.symbol)")
        }
        if let clickSounds {
            settings.prefs.clickSounds = clickSounds
            done.append("click sounds \(clickSounds ? "on" : "off")")
        }
        if let twentyFourHour {
            settings.prefs.use24Hour = twentyFourHour
            done.append(twentyFourHour ? "24-hour time" : "12-hour time")
        }
        return done.isEmpty ? "Nothing to change." : "Done: \(done.formatted(.list(type: .and)))."
    }

    // MARK: - Night clock

    enum NightClockAction { case startNow, turnOn, turnOff }

    func nightClock(_ action: NightClockAction?, idleMinutes: Int?, redAfterMidnight: Bool?) -> String {
        if DankHomeApp.isPhone, action == .startNow { return "The night clock is for the iPad on the wall." }
        var done: [String] = []
        if let idleMinutes {
            settings.prefs.nightIdleMinutes = idleMinutes.clamped(to: 1...120)
            settings.prefs.nightEnabled = true
            done.append("the night clock starts after \(settings.prefs.nightIdleMinutes) minutes idle")
        }
        if let redAfterMidnight {
            settings.prefs.nightRedAfterMidnight = redAfterMidnight
            done.append("red after midnight \(redAfterMidnight ? "on" : "off")")
        }
        switch action {
        case .startNow:
            idle.sleep(settings.prefs)
            done.insert("night clock on", at: 0)
        case .turnOn:
            settings.prefs.nightEnabled = true
            if idleMinutes == nil { done.append("the night clock will start after \(settings.prefs.nightIdleMinutes) minutes idle") }
        case .turnOff:
            settings.prefs.nightEnabled = false
            done.append("the night clock is off")
        case nil:
            break
        }
        return done.isEmpty ? "Nothing to change." : "Okay, \(done.formatted(.list(type: .and)))."
    }

    // MARK: - Wake-up light

    func wakeUpLight(on: Bool?, hour: Int?, minute: Int?, room: String?, days: Set<Int>?, fadeMinutes: Int?) -> String {
        var alarm = settings.prefs.wakeAlarm
        if on == false {
            alarm.isEnabled = false
            settings.prefs.wakeAlarm = alarm
            return "The wake-up light is off."
        }
        if let hour { alarm.hour = hour.clamped(to: 0...23); alarm.minute = (minute ?? 0).clamped(to: 0...59) }
        if let days { alarm.days = days }
        if let fadeMinutes { alarm.fadeMinutes = fadeMinutes.clamped(to: 5...90) }
        let rooms = Array(Set(home.lights.filter { $0.brightness != nil }.map(\.roomName))).sorted()
        if let room {
            guard let match = rooms.first(where: { $0.lowercased() == room.lowercased() })
                    ?? rooms.first(where: { $0.localizedCaseInsensitiveContains(room) || room.localizedCaseInsensitiveContains($0) }) else {
                return "There are no dimmable lights in \(room). Rooms: \(rooms.joined(separator: ", "))."
            }
            alarm.room = match
        }
        if alarm.room.isEmpty {
            alarm.room = rooms.first { $0.localizedCaseInsensitiveContains("bed") } ?? rooms.first ?? ""
        }
        guard !alarm.room.isEmpty else { return "There are no dimmable lights for a wake-up light." }
        alarm.isEnabled = true
        settings.prefs.wakeAlarm = alarm
        let time = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
        return "Wake-up light set for \(time.formatted(date: .omitted, time: .shortened)), \(Routine.daysText(alarm.days).lowercased()), "
            + "fading in the \(alarm.room) over \(alarm.fadeMinutes) minutes."
    }

    // MARK: - Adaptive lighting

    func adaptiveLighting(on: Bool?, daytimeKelvin: Int?, nightKelvin: Int?) -> String {
        if let daytimeKelvin { settings.prefs.adaptiveDayKelvin = Double(daytimeKelvin).clamped(to: 3500...6500) }
        if let nightKelvin { settings.prefs.adaptiveNightKelvin = Double(nightKelvin).clamped(to: 2000...3000) }
        if let on { settings.prefs.adaptiveLighting = on }
        else if daytimeKelvin != nil || nightKelvin != nil { settings.prefs.adaptiveLighting = true }
        let prefs = settings.prefs
        guard prefs.adaptiveLighting else { return "Adaptive lighting is off." }
        return "Adaptive lighting is on: \(Int(prefs.adaptiveDayKelvin))K by day, \(Int(prefs.adaptiveNightKelvin))K at night."
    }

    // MARK: - Scenes

    /// Saves the lights as they are right now (one room, or the whole home with the
    /// thermostat) as a scene button, replacing one with the same name.
    func saveScene(name: String, room: String?) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).localizedCapitalized
        guard !name.isEmpty else { return "Say what to call the scene." }
        var lights = home.lights.filter(\.isReachable)
        var place = ""
        if let room, !["all", "home", "house", "everything", "everywhere"].contains(room.lowercased()) {
            guard let match = home.roomNames.first(where: { $0.localizedCaseInsensitiveContains(room) || room.localizedCaseInsensitiveContains($0) }) else {
                return "There's no room called \(room). Rooms: \(home.roomNames.joined(separator: ", "))."
            }
            lights = lights.filter { $0.roomName == match }
            place = " in the \(match)"
        }
        guard !lights.isEmpty else { return "There are no lights\(place) to save." }
        var scene = CustomScene()
        scene.lights = lights.map { $0.isOn ? $0.currentSetting : LightSetting(key: $0.key, on: false) }
        if place.isEmpty, let thermostat = home.thermostats.first {
            scene.thermostat = ThermostatSetting(mode: thermostat.mode.rawValue,
                                                 targetC: thermostat.mode == .off ? nil : thermostat.targetC)
        }
        var replaced = false
        settings.editSceneButtons(home: home) { buttons in
            if let index = buttons.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                buttons[index].action = .custom(scene)
                replaced = true
            } else {
                buttons.append(SceneButton(name: name, symbol: Self.symbol(for: name), action: .custom(scene)))
            }
        }
        let on = lights.filter(\.isOn).count
        return "\(replaced ? "Updated" : "Saved") \(name) with \(lights.count) light\(lights.count == 1 ? "" : "s")\(place) "
            + "(\(on) on)\(scene.thermostat != nil ? " and the thermostat" : ""). Say “run \(name)” any time."
    }

    static func symbol(for name: String) -> String {
        let name = name.lowercased()
        let symbols: [(words: [String], symbol: String)] = [
            (["movie", "tv", "film", "show"], "tv.fill"), (["night", "bed", "sleep"], "moon.stars.fill"),
            (["morning", "wake", "sunrise"], "sunrise.fill"), (["dinner", "eat", "cook", "kitchen"], "fork.knife"),
            (["party", "celebrat"], "party.popper.fill"), (["read", "book", "study"], "book.fill"),
            (["relax", "chill", "cozy", "calm"], "sofa.fill"), (["game", "gaming"], "gamecontroller.fill"),
            (["work", "focus", "office"], "briefcase.fill"), (["romantic", "date", "love"], "heart.fill"),
            (["bright", "day", "clean"], "sun.max.fill"), (["away", "leave", "leaving"], "figure.walk"),
            (["workout", "gym"], "dumbbell.fill"), (["music", "jam"], "music.note"),
        ]
        return symbols.first { entry in entry.words.contains { name.contains($0) } }?.symbol ?? "sparkles"
    }

    // MARK: - Timers and routines

    enum AutomationAction { case cancelTimers, deleteRoutine, pauseRoutine, resumeRoutine }

    func manageAutomations(_ action: AutomationAction, routine name: String?) -> String {
        if action == .cancelTimers {
            let count = automation.timers.count
            automation.cancelAllTimers()
            return count == 0 ? "There are no timers." : count == 1 ? "Canceled the timer." : "Canceled \(count) timers."
        }
        let routines = automation.routines
        let match: Routine? = if let name, !name.isEmpty {
            routines.first { $0.command.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.command) }
        } else {
            routines.count == 1 ? routines.first : nil
        }
        guard let routine = match else {
            if routines.isEmpty { return "There are no routines." }
            return "Which routine? \(routines.map { "“\($0.command)” \($0.scheduleText.lowercased())" }.joined(separator: "; "))."
        }
        switch action {
        case .deleteRoutine:
            automation.remove(routine)
            return "Deleted the routine “\(routine.command)”."
        case .pauseRoutine:
            automation.setEnabled(false, for: routine.id)
            return "Paused “\(routine.command)”."
        case .resumeRoutine:
            automation.setEnabled(true, for: routine.id)
            return "“\(routine.command)” is back on, \(routine.scheduleText.lowercased())."
        case .cancelTimers:
            return ""
        }
    }

    // MARK: - Screens

    func open(_ screen: AppNavigator.Screen) -> String {
        navigator.request = screen
        return switch screen {
        case .whatsOn: "Here's what's on."
        case .settings: "Opening Settings."
        case .automations: "Here are your timers and routines."
        }
    }

    // MARK: - For questions

    /// The app's own state, so the assistant can answer "when is my alarm?".
    var summary: String {
        let prefs = settings.prefs
        var parts = ["background \(prefs.theme.title)", "temperatures in \(prefs.temperatureUnit.symbol)"]
        if !DankHomeApp.isPhone {
            parts.append(prefs.nightEnabled ? "night clock after \(prefs.nightIdleMinutes) min idle" : "night clock off")
        }
        let alarm = prefs.wakeAlarm
        if alarm.isEnabled {
            let time = Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now
            parts.append("wake-up light \(time.formatted(date: .omitted, time: .shortened)) \(Routine.daysText(alarm.days).lowercased()) in the \(alarm.room)")
        } else {
            parts.append("wake-up light off")
        }
        parts.append(prefs.adaptiveLighting ? "adaptive lighting on" : "adaptive lighting off")
        if let room = home.selectedRoom { parts.append("dashboard showing the \(room)") }
        return "APP: \(parts.joined(separator: "; "))."
    }
}
