//
//  QuickAppCommands.swift
//  DankHome
//
//  App commands handled instantly, without the language model: the night clock,
//  which room the dashboard shows, °F/°C, adaptive lighting, the wake-up light,
//  saving a scene, opening screens, background themes, and shade or fan levels.
//

import Foundation

extension QuickCommands {
    /// `text` is already normalized (see `QuickCommands.normalize`).
    func appCommand(_ text: String) -> String? {
        levelCommand(text)
            ?? app.flatMap { app in
                nightClockCommand(text, app)
                    ?? roomCommand(text, app)
                    ?? unitsCommand(text, app)
                    ?? adaptiveCommand(text, app)
                    ?? wakeCommand(text, app)
                    ?? saveCommand(text, app)
                    ?? openCommand(text, app)
                    ?? themeCommand(text, app)
            }
    }

    // MARK: Shades and fans

    /// "set the shades to 40%", "ceiling fan to 60 percent".
    private func levelCommand(_ text: String) -> String? {
        guard let g = text.captures("^(?:set |open |close |put |turn )?(?:the )?(.+?) (?:to |at )(\\d{1,3})(?: ?%| percent)?$"),
              let level = Int(g[1]), (0...100).contains(level),
              home.devices.contains(where: { ($0.kind == .shade || $0.kind == .fan) && $0.name.lowercased().contains(g[0]) }) else {
            return nil
        }
        return home.assistantSetLevel(g[0], level: level).replacingOccurrences(of: "Success. ", with: "")
    }

    // MARK: Night clock

    private func nightClockCommand(_ text: String, _ app: AppControl) -> String? {
        if text.captures("^(?:start |turn on |go to |enter |show |switch to )?(?:the )?(?:night clock|night mode|sleep mode|screen saver|screensaver)$") != nil
            || text.captures("^(?:dim|turn off|sleep|darken) (?:the )?(?:screen|display)$") != nil {
            return app.nightClock(AppControl.NightClockAction.startNow, idleMinutes: nil, redAfterMidnight: nil)
        }
        if text.captures("^(?:turn off|disable|stop) (?:the )?night clock$") != nil {
            return app.nightClock(AppControl.NightClockAction.turnOff, idleMinutes: nil, redAfterMidnight: nil)
        }
        return nil
    }

    // MARK: Dashboard room

    /// "show the kitchen", "show all rooms". Only real room names count.
    private func roomCommand(_ text: String, _ app: AppControl) -> String? {
        guard let g = text.captures("^(?:show|switch to|go to|view)(?: me)? (?:the )?(.+)$") else { return nil }
        let name = g[0]
        let all = ["all rooms", "all", "every room", "everything", "whole house", "the whole house", "all the rooms"]
        if all.contains(name) {
            return app.changeDashboard(section: nil, show: nil, room: "all", units: nil, clickSounds: nil, twentyFourHour: nil)
        }
        // "the living room" or "the living", "the office room" or "the office".
        let trimmed = name.hasSuffix(" room") ? String(name.dropLast(5)) : name
        guard let room = home.roomNames.first(where: { [name, trimmed].contains($0.lowercased()) }) else { return nil }
        return app.changeDashboard(section: nil, show: nil, room: room, units: nil, clickSounds: nil, twentyFourHour: nil)
    }

    // MARK: Units

    private func unitsCommand(_ text: String, _ app: AppControl) -> String? {
        guard let g = text.captures("^(?:switch to|use|change to|set (?:the )?units to|show(?: temperatures in)?) (celsius|fahrenheit|metric|imperial)$") else {
            return nil
        }
        return app.changeDashboard(section: nil, show: nil, room: nil, units: g[0], clickSounds: nil, twentyFourHour: nil)
    }

    // MARK: Adaptive lighting

    private func adaptiveCommand(_ text: String, _ app: AppControl) -> String? {
        let on: Bool
        if let g = text.captures("^turn (on|off) (?:the )?adaptive (?:lighting|lights)$")
            ?? text.captures("^adaptive (?:lighting|lights) (on|off)$") {
            on = g[0] == "on"
        } else if let g = text.captures("^(enable|disable|start|stop) (?:the )?adaptive (?:lighting|lights)$") {
            on = g[0] == "enable" || g[0] == "start"
        } else {
            return nil
        }
        return app.adaptiveLighting(on: on, daytimeKelvin: nil, nightKelvin: nil)
    }

    // MARK: Wake-up light

    /// "wake me up at 6 30 am on weekdays", "turn off the wake up light".
    private func wakeCommand(_ text: String, _ app: AppControl) -> String? {
        if text.captures("^(?:turn off|cancel|disable|stop|delete) (?:the |my )?(?:wake up light|wakeup light|wake light|wake up alarm|alarm)$") != nil {
            return app.wakeUpLight(on: false, hour: nil, minute: nil, room: nil, days: nil, fadeMinutes: nil)
        }
        guard let g = text.captures("^(?:wake me(?: up)?|set (?:the |my )?(?:wake up light|alarm) (?:for|to)) (?:at )?(\\d{1,2})(?: (\\d{2}))?(?: ?(am|pm|a m|p m))?(?: (?:on )?(weekdays|weekends|every day|everyday|daily))?$"),
              var hour = Int(g[0]), (1...23).contains(hour) || (hour == 0 && g[2].isEmpty) else { return nil }
        let minute = Int(g[1]) ?? 0
        guard (0...59).contains(minute) else { return nil }
        if g[2].hasPrefix("p"), hour < 12 { hour += 12 }
        if g[2].hasPrefix("a"), hour == 12 { hour = 0 }
        let days: Set<Int>? = switch g[3] {
        case "weekdays": Routine.weekdays
        case "weekends": Routine.weekends
        case "every day", "everyday", "daily": []
        default: nil
        }
        return app.wakeUpLight(on: true, hour: hour, minute: minute, room: nil, days: days, fadeMinutes: nil)
    }

    // MARK: Save a scene

    /// "save this as movie night", "save the kitchen as dinner".
    private func saveCommand(_ text: String, _ app: AppControl) -> String? {
        guard let g = text.captures("^save (?:the )?(.+?) as (?:a scene (?:called |named )?)?(.+?)(?: scene)?$") else { return nil }
        let what = g[0]
        let everything = ["this", "these", "it", "lights", "the lights", "current lights", "everything", "scene",
                          "current scene", "the scene", "all the lights", "all lights", "how it is", "this setup"]
        if everything.contains(what) {
            return app.saveScene(name: g[1], room: nil)
        }
        let room = what.replacingOccurrences(of: " lights$", with: "", options: .regularExpression)
        guard home.roomNames.contains(where: { $0.lowercased() == room }) else { return nil }
        return app.saveScene(name: g[1], room: room)
    }

    // MARK: Screens

    private func openCommand(_ text: String, _ app: AppControl) -> String? {
        guard let g = text.captures("^(?:open|show)(?: me)? (?:the |my )?(settings|automations|routines|timers|what s on|whats on|energy|power)(?: screen| page| view)?$") else {
            return nil
        }
        switch g[0] {
        case "settings": return app.open(AppNavigator.Screen.settings)
        case "automations", "routines", "timers": return app.open(AppNavigator.Screen.automations)
        default: return app.open(AppNavigator.Screen.whatsOn)
        }
    }

    // MARK: Background

    private func themeCommand(_ text: String, _ app: AppControl) -> String? {
        let names = BackgroundTheme.allCases.map(\.rawValue).joined(separator: "|")
        guard let g = text.captures("^(?:use|switch to|change to|set|make it|change the background to|set the background to) (?:the )?(\(names))(?: theme| background| look)?$") else {
            return nil
        }
        return app.changeLook(theme: g[0], accent: nil, appFont: nil, clockFont: nil, clockColor: nil, weatherEffects: nil)
    }
}
