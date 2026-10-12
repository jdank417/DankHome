//
//  QuickAnswers.swift
//  DankHome
//
//  Everyday questions answered straight from the home's state, without the
//  language model: which lights are on, is the door locked, how warm is it, will
//  it rain. Anything that isn't a clear match returns nil and goes to the model.
//

import Foundation

extension QuickCommands {
    /// `text` is already normalized: lowercased, no punctuation ("what's" is "what s"),
    /// and filler words like "please" and "now" removed ("right now" is "right").
    func answer(_ text: String) -> String? {
        lightsAnswer(text)
            ?? deviceAnswer(text)
            ?? temperatureAnswer(text)
            ?? weatherAnswer(text)
            ?? powerAnswer(text)
            ?? timerAnswer(text)
            ?? timeAnswer(text)
    }

    private static let whatIs = "(?:what s|whats|what is)"

    // MARK: Lights

    private func lightsAnswer(_ text: String) -> String? {
        let place: String?
        if let g = text.captures("^(?:which|what) lights? (?:are|is) (?:on|still on|left on)(?: in (?:the )?(.+))?$")
            ?? text.captures("^(?:are|is) (?:there )?(?:any|the) lights? (?:on|still on|left on)(?: in (?:the )?(.+))?$") {
            place = g[0].isEmpty ? nil : g[0]
        } else if let g = text.captures("^(?:are|is) (?:the )?(.+?) lights? on$") {
            place = g[0]
        } else {
            return nil
        }
        var lights = home.lights
        var whereText = ""
        if let place, !Self.everywhere.contains(place) {
            guard let room = home.roomNames.first(where: { $0.lowercased() == place || $0.lowercased().contains(place) }) else {
                // Maybe it's one light's name: "is the porch light on".
                guard let light = home.lights.first(where: { $0.name.lowercased().contains(place) }) else { return nil }
                return Self.describe(light)
            }
            lights = lights.filter { $0.roomName == room }
            whereText = " in the \(room)"
        }
        let on = lights.filter { $0.isOn && $0.isReachable }
        if on.isEmpty { return "All the lights\(whereText) are off." }
        let names = on.count > 6 ? on.prefix(5).map(\.name) + ["\(on.count - 5) more"] : on.map(\.name)
        return "\(names.formatted(.list(type: .and))) \(on.count == 1 ? "is" : "are") on\(whereText)."
    }

    private static let everywhere: Set<String> = ["house", "home", "the house", "everywhere", "all rooms"]

    private static func describe(_ light: Light) -> String {
        guard light.isReachable else { return "\(light.name) isn't responding." }
        guard light.isOn else { return "\(light.name) is off." }
        return "\(light.name) is on\(light.brightness.map { " at \(Int($0))%" } ?? "")."
    }

    // MARK: Locks, doors and devices

    private func deviceAnswer(_ text: String) -> String? {
        guard let g = text.captures("^(?:is|are) (?:the |my )?(.+?) (locked|unlocked|open|closed|shut|on|off|running)$") else { return nil }
        let target = g[0]
        // "are the doors locked", "is everything locked"
        if ["doors", "the doors", "all the doors", "everything", "house", "the house"].contains(target), ["locked", "unlocked"].contains(g[1]) {
            let locks = home.devices.filter { $0.kind == .lock }
            guard !locks.isEmpty else { return nil }
            let unlocked = locks.filter { !$0.active || $0.hasProblem || !$0.isReachable }
            if unlocked.isEmpty { return locks.count == 1 ? "\(locks[0].name) is locked." : "All \(locks.count) doors are locked." }
            return unlocked.map { "\($0.name) is \($0.status.lowercased())" }.formatted(.list(type: .and)) + "."
        }
        let name = target.replacingOccurrences(of: " light$", with: "", options: .regularExpression)
        if let device = home.devices.first(where: { $0.name.lowercased() == name })
            ?? home.devices.first(where: { $0.name.lowercased().contains(name) || "\($0.roomName) \($0.name)".lowercased().contains(name) }) {
            return "\(device.name) is \(device.status.lowercased())."
        }
        if ["on", "off"].contains(g[1]), let light = home.lights.first(where: { $0.name.lowercased().contains(name) }) {
            return Self.describe(light)
        }
        return nil
    }

    // MARK: Inside temperature

    private func temperatureAnswer(_ text: String) -> String? {
        let prefs = settings.prefs
        let inside = text.captures("^\(Self.whatIs) (?:the )?(?:temperature|temp)(?: inside| in here| in the house| at home)$") != nil
            || text.captures("^how (?:warm|cold|hot) is it (?:inside|in here|in the house)$") != nil
            || text.captures("^\(Self.whatIs) (?:the )?(?:thermostat|heat|ac) (?:set to|at|on)$") != nil
        let either = text.captures("^\(Self.whatIs) (?:the )?(?:temperature|temp)$") != nil
        guard inside || either, let thermostat = home.thermostats.first else { return nil }
        var reply = "It's \(prefs.formatTemperature(celsius: thermostat.currentC)) inside"
        if either, let current = weather?.current {
            reply += " and \(prefs.formatTemperature(celsius: current.temperature)) outside"
        }
        reply += "."
        switch (thermostat.mode, thermostat.activity) {
        case (.off, _): reply += " The thermostat is off."
        case (_, .heating): reply += " Heating to \(prefs.formatTemperature(celsius: thermostat.targetC))."
        case (_, .cooling): reply += " Cooling to \(prefs.formatTemperature(celsius: thermostat.targetC))."
        default: reply += " The thermostat is set to \(prefs.formatTemperature(celsius: thermostat.targetC))."
        }
        return reply
    }

    // MARK: Weather

    private func weatherAnswer(_ text: String) -> String? {
        guard let weather, let current = weather.current else { return nil }
        let prefs = settings.prefs
        if let g = text.captures("^(?:will|is) it (?:going to )?(rain|snow)(?: today| later| this afternoon| this evening| tonight| soon)?$")
            ?? text.captures("^(?:do|should) i (?:need|bring|take) (?:an )?(umbrella|a jacket|a coat)(?: today)?$") {
            let wantsSnow = g[0] == "snow"
            let codes: (Int) -> Bool = wantsSnow ? Self.isSnow : Self.isRain
            if let hour = weather.hours.prefix(12).first(where: { codes($0.code) }) {
                return "\(wantsSnow ? "Snow" : "Rain") is likely around \(hour.id.formatted(.dateTime.hour()))."
            }
            if g[0].hasPrefix("a ") {
                let low = weather.hours.prefix(12).map(\.temperature).min() ?? current.low
                return "No rain coming. It gets down to \(prefs.formatTemperature(celsius: low)), so maybe a light layer."
            }
            return "No \(wantsSnow ? "snow" : "rain") in the next 12 hours."
        }
        let asked = text.captures("^\(Self.whatIs) (?:the )?weather(?: like)?(?: today| right| outside)?$") != nil
            || text.captures("^how (?:cold|hot|warm) is it(?: outside| out| out there)?$") != nil
            || text.captures("^\(Self.whatIs) it like outside$") != nil
            || text.captures("^\(Self.whatIs) (?:the )?(?:temperature|temp) outside$") != nil
        guard asked else { return nil }
        let place = weather.placeName.isEmpty ? "" : " in \(weather.placeName)"
        var reply = "It's \(prefs.formatTemperature(celsius: current.temperature)) and \(WeatherCode.description(current.code).lowercased())\(place). "
        reply += "High \(prefs.formatTemperature(celsius: current.high)), low \(prefs.formatTemperature(celsius: current.low))."
        if let rain = weather.hours.prefix(8).first(where: { Self.isRain($0.code) }) {
            reply += " Rain likely around \(rain.id.formatted(.dateTime.hour()))."
        }
        return reply
    }

    private static func isRain(_ code: Int) -> Bool { (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code) }
    private static func isSnow(_ code: Int) -> Bool { (71...77).contains(code) || code == 85 || code == 86 }

    // MARK: Power

    private func powerAnswer(_ text: String) -> String? {
        let asked = text.captures("^\(Self.whatIs) (?:on|using power|using electricity|using the most power|left on)$") != nil
            || text.captures("^how much (?:power|electricity|energy) (?:are we|am i|is the house|is the home) using(?: right)?$") != nil
        guard asked else { return nil }
        let devices = home.poweredItems().filter { $0.source != .light }
        let lightsOn = home.lights.filter { $0.isOn && $0.isReachable }.count
        var parts: [String] = []
        if let total = home.totalWatts { parts.append("Using \(EnergyFormat.watts(total)) right now.") }
        if let top = devices.first {
            var detail = top.name
            if let watts = top.watts { detail += " (\(EnergyFormat.watts(watts)))" }
            if let since = top.since { detail += " has been on \(EnergyFormat.duration(Date.now.timeIntervalSince(since)))" } else { detail += " is on" }
            parts.append(detail + ".")
        }
        parts.append(lightsOn == 0 ? "All lights are off." : lightsOn == 1 ? "1 light is on." : "\(lightsOn) lights are on.")
        return parts.joined(separator: " ")
    }

    // MARK: Timers and time

    private func timerAnswer(_ text: String) -> String? {
        guard let automation,
              text.captures("^(?:what|which|any) timers?(?: are| is)?(?: set| running| on)?$") != nil
                || text.captures("^(?:is there|are there) (?:a |any )?timers?(?: set| running| on)?$") != nil else { return nil }
        guard !automation.timers.isEmpty else { return "There are no timers." }
        return automation.timers.map {
            "\($0.command) at \($0.fireDate.formatted(date: .omitted, time: .shortened))"
        }.formatted(.list(type: .and)).capitalizedFirst + "."
    }

    private func timeAnswer(_ text: String) -> String? {
        guard text.captures("^(?:what time is it|\(Self.whatIs) the time)$") != nil else { return nil }
        return "It's \(Date.now.formatted(date: .omitted, time: .shortened))."
    }
}
