//
//  QuickCommands.swift
//  DankHome
//
//  Everyday commands handled instantly, without the language model. Anything that
//  isn't a clear, simple match returns nil and goes to the model instead.
//

import Foundation

struct QuickCommands {
    let home: HomeStore
    let music: MusicStore
    let settings: AppSettings
    var automation: AutomationStore?
    var weather: WeatherStore?
    var app: AppControl?

    /// What the instant path managed: the replies for what it did, and whatever is
    /// left for the model ("turn off the kitchen and make it cozy" leaves "make it cozy").
    struct Result {
        var replies: [String] = []
        var remainder: String?
    }

    private static let fillers = ["please", "can you", "could you", "would you", "hey", "dankhome", "dank home", "now"]
    /// Words that mean the request has conditions or timing the model should handle.
    private static let complex: Set<String> = ["if", "when", "until", "after", "before", "minute", "minutes", "hour",
                                                "hours", "and", "then", "but", "except", "every", "tomorrow", "tonight", "why", "what"]
    private static let colors = ["warm white", "cool white", "soft white", "daylight", "white", "red", "orange", "amber",
                                 "yellow", "green", "teal", "cyan", "blue", "indigo", "purple", "violet", "magenta", "pink"]
    private static let everything: Set<String> = ["", "all", "everything", "everywhere", "house", "home", "the house",
                                                  "the home", "all lights", "lights", "light", "every light", "all the lights"]

    /// Words a command can start with, so "turn off the kitchen and lock the front door"
    /// can be split into two commands but "the living and dining room" is left whole.
    private static let verbs: Set<String> = ["turn", "switch", "set", "dim", "brighten", "make", "lock", "unlock", "open",
                                             "close", "shut", "run", "start", "activate", "play", "pause", "resume", "skip",
                                             "put", "cancel", "stop", "next", "previous"]

    /// Handles as much as it can instantly, in order, and hands back the rest.
    func run(_ input: String) async -> Result {
        let text = Self.normalize(input)
        let parts = text.components(separatedBy: " and then ")
            .flatMap { $0.components(separatedBy: " then ") }
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let splittable = parts.count > 1 && parts.allSatisfy { part in
            part.split(separator: " ").first.map { Self.verbs.contains(String($0)) } ?? false
        }
        guard splittable else {
            if let reply = await single(text) { return Result(replies: [reply]) }
            return Result(remainder: input)
        }
        var result = Result()
        for (index, part) in parts.enumerated() {
            guard let reply = await single(part) else {
                result.remainder = parts[index...].joined(separator: " and ")
                break
            }
            result.replies.append(reply)
        }
        return result
    }

    /// The reply when everything was handled instantly, else nil.
    func handle(_ input: String) async -> String? {
        let result = await run(input)
        return result.remainder == nil ? result.replies.joined(separator: " ") : nil
    }

    static func normalize(_ input: String) -> String {
        var text = " " + input.lowercased().replacingOccurrences(of: "[^a-z0-9% ]", with: " ", options: .regularExpression) + " "
        for filler in fillers { text = text.replacingOccurrences(of: " \(filler) ", with: " ") }
        return text.replacingOccurrences(of: " +", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private func single(_ text: String) async -> String? {
        if let reply = timerCommand(text) { return reply }
        if let reply = answer(text) { return reply }
        if let reply = appCommand(text) { return reply }

        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 9, Self.complex.isDisjoint(with: words) else { return nil }

        if let reply = await musicCommand(text) { return reply }
        if let reply = thermostatCommand(text) { return reply }
        if let reply = deviceCommand(text) { return reply }
        if let reply = lightsCommand(text) { return reply }
        return sceneCommand(text)
    }

    // MARK: Timers

    /// "turn off the lights in 30 minutes", "cancel the timers".
    private func timerCommand(_ text: String) -> String? {
        guard let automation else { return nil }
        if text.captures("^(?:cancel|stop|clear|delete) (?:the |all |all the |my )*timers?$") != nil {
            let count = automation.timers.count
            automation.cancelAllTimers()
            return count == 0 ? "There are no timers." : count == 1 ? "Canceled the timer." : "Canceled \(count) timers."
        }
        guard let timer = TimerPhrase.parse(text) else { return nil }
        let scheduled = automation.addTimer(timer.command, after: timer.delay)
        return "Okay, I'll \(timer.command) at \(scheduled.fireDate.formatted(date: .omitted, time: .shortened))."
    }

    // MARK: Music

    private func musicCommand(_ text: String) async -> String? {
        let actions: [String: [String]] = [
            "pause": ["pause", "pause music", "pause the music", "stop music", "stop the music"],
            "play": ["play", "play music", "resume", "resume music", "unpause"],
            "next": ["next", "next song", "skip", "skip song", "skip this song", "next track"],
            "previous": ["previous", "previous song", "last song", "go back", "back"],
        ]
        guard let action = actions.first(where: { $0.value.contains(text) })?.key else { return nil }
        guard music.isAuthorized else { return "Connect Apple Music first." }
        return await music.assistantControl(action: action, playlist: nil)
    }

    // MARK: Thermostat

    private func thermostatCommand(_ text: String) -> String? {
        let device = "(?:thermostat|temperature|temp|heat|heating|ac|air conditioning|air)"
        if let groups = text.captures("^(?:set |make |put |turn )?(?:the )?\(device)(?: up| down)?(?: to| at)? (\\d{2})(?: degrees)?$"),
           let degrees = Double(groups[0]) {
            return home.assistantThermostat(temperature: degrees, mode: nil, unit: settings.prefs.temperatureUnit)
        }
        if let groups = text.captures("^(?:set |turn |switch )?(?:the )?(heat|heating|ac|air conditioning|thermostat|air) (on|off)$")
            ?? text.captures("^(?:turn |switch )(on|off) (?:the )?(heat|heating|ac|air conditioning|thermostat|air)$").map({ [$0[1], $0[0]] }) {
            let (device, power) = (groups[0], groups[1])
            let mode = power == "off" ? "off" : device.hasPrefix("heat") ? "heat" : device == "thermostat" ? "auto" : "cool"
            return home.assistantThermostat(temperature: nil, mode: mode, unit: settings.prefs.temperatureUnit)
        }
        return nil
    }

    // MARK: Devices

    private func deviceCommand(_ text: String) -> String? {
        let actions: [String: Bool] = ["lock": true, "unlock": false, "open": true, "close": false, "shut": false]
        var verb: String?, target: String?, active: Bool?
        if let g = text.captures("^(lock|unlock|open|close|shut) (?:the )?(.+)$") {
            (verb, target, active) = (g[0], g[1], actions[g[0]])
        } else if let g = text.captures("^(?:turn|switch) (on|off) (?:the )?(.+)$") ?? text.captures("^(?:turn|switch) (?:the )?(.+?) (on|off)$").map({ [$0[1], $0[0]] }) {
            (verb, target, active) = (g[0], g[1], g[0] == "on")
        }
        guard let verb, let target, let active,
              let device = home.devices.first(where: { $0.name.lowercased() == target || $0.name.lowercased().contains(target) }) else {
            return nil
        }
        // "turn on the porch" should still reach a light called Porch.
        if (verb == "on" || verb == "off"), device.kind == .lock || device.kind == .garage { return nil }
        return home.assistantControlDevice(device.name, active: active).replacingOccurrences(of: "Success. ", with: "")
    }

    // MARK: Lights

    private func lightsCommand(_ text: String) -> String? {
        let lead = "(?:turn|switch|shut|put)"
        let the = "(?:the |all |all the )*"
        // "turn off the kitchen", "turn the kitchen off", "kitchen off", "lights on"
        if let g = text.captures("^\(lead) (on|off) \(the)(.*)$") {
            return applyLights(target: g[1], on: g[0] == "on")
        }
        if let g = text.captures("^\(lead) \(the)(.*?) ?(on|off)$") ?? text.captures("^\(the)(.*?) ?(on|off)$") {
            return applyLights(target: g[0], on: g[1] == "on")
        }
        // "dim the living room to 30%", "set kitchen lights to 80 percent"
        if let g = text.captures("^(?:set|dim|turn|make|put|brighten) \(the)(.*?) (?:to |at )?(\\d{1,3})(?: ?%| percent)?$"),
           let level = Int(g[1]), (1...100).contains(level) {
            return applyLights(target: g[0], brightness: level)
        }
        // "make the bedroom blue", "set the lights to warm white"
        let colorPattern = Self.colors.joined(separator: "|")
        if let g = text.captures("^(?:set|make|turn|change) \(the)(.*?) (?:to )?(\(colorPattern))$") {
            return applyLights(target: g[0], color: g[1])
        }
        return nil
    }

    private func applyLights(target: String, on: Bool? = nil, brightness: Int? = nil, color: String? = nil) -> String? {
        var target = target.trimmingCharacters(in: .whitespaces)
        for suffix in [" lights", " light", " lamps", " room lights"] where target.hasSuffix(suffix) && target != suffix.trimmingCharacters(in: .whitespaces) {
            target = String(target.dropLast(suffix.count))
        }
        if target.hasPrefix("in the ") { target = String(target.dropFirst(7)) }

        var room: String?
        var light: String?
        if !Self.everything.contains(target) {
            if let match = home.roomNames.first(where: { $0.lowercased() == target || $0.lowercased().contains(target) }) {
                room = match
            } else if let match = home.lights.first(where: { $0.name.lowercased() == target || $0.name.lowercased().contains(target) }) {
                light = match.name
            } else {
                return nil  // Unknown name: let the model work it out.
            }
        }
        let result = home.assistantControlLights(room: room, light: light, on: on, brightness: brightness, color: color)
        return result.replacingOccurrences(of: "Success. ", with: "")
    }

    // MARK: Scenes

    private func sceneCommand(_ text: String) -> String? {
        guard let g = text.captures("^(?:run |start |activate |set |turn on |do )?(?:the )?(.+?)(?: scene| mode)?$") else { return nil }
        let wanted = g[0].replacingOccurrences(of: " ", with: "")
        let buttons = settings.sceneButtons(home: home)
        if let button = buttons.first(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == wanted }) {
            SceneRunner(home: home, music: music, settings: settings).run(button)
            return "Ran \(button.name)."
        }
        guard let scene = home.scenes.first(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "") == wanted }) else {
            return nil
        }
        return home.assistantRunScene(scene.name)
    }
}
