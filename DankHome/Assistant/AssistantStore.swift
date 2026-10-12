//
//  AssistantStore.swift
//  DankHome
//

import AVFoundation
import FoundationModels
import SwiftUI

/// Home assistant powered by Apple Intelligence's on-device model. It controls the
/// home through tools, so nothing leaves the iPad.
@Observable
final class AssistantStore {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        var fromUser: Bool
        var text: String
    }

    static let suggestions = [
        "Turn off all the lights",
        "Make the living room warm white at 40%",
        "Set the thermostat to 70",
        "Lock the front door",
        "Will it be cold tonight?",
        "Which lights are on?",
        "Turn off the lights in 30 minutes",
        "Every night at 10, run Good Night",
        "Save this as Movie Night",
        "Wake me up at 6:30 on weekdays",
        "Switch to the ocean background",
        "Turn on adaptive lighting",
        "Show what's on",
    ]

    /// Suggestions that fit the time of day, using the home's own scene names.
    static func suggestions(at date: Date = .now, scenes: [String]) -> [String] {
        let hour = Calendar.current.component(.hour, from: date)
        let scene = { (words: [String]) in scenes.first { name in words.contains { name.lowercased().contains($0) } } }
        var list: [String]
        switch hour {
        case 5..<11:
            list = ["What's the weather today?", "Turn on the kitchen lights", "Open the shades"]
            if let morning = scene(["morning", "bright", "wake"]) { list.insert("Run \(morning)", at: 0) }
        case 11..<17:
            list = ["Will it rain this afternoon?", "Set the thermostat to 70", "Show what's on"]
        case 17..<21:
            list = ["Make the living room warm white at 40%", "Save this as Movie Night", "Will it be cold tonight?"]
            if let evening = scene(["movie", "relax", "dinner"]) { list.insert("Run \(evening)", at: 0) }
        default:
            list = ["Turn off all the lights and lock the front door", "Wake me up at 6:30 on weekdays", "Night mode"]
            if let night = scene(["night", "sleep", "bed"]) { list.insert("Run \(night)", at: 0) }
        }
        list.append("Which lights are on?")
        return Array(NSOrderedSet(array: list).array as! [String]).prefix(5).map { $0 }
    }

    private(set) var messages: [Message] = []
    private(set) var isResponding = false

    /// Why the assistant can't run on this device, or nil when it can.
    var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available: nil
        case .unavailable(.deviceNotEligible): "This device doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    /// Each kind of request gets its own small session. Fewer tools means a shorter
    /// prompt, and questions skip tools entirely, so the model answers in one pass
    /// instead of calling a tool and then answering.
    enum Mode: Hashable {
        /// "make the living room cozy": lights, devices, thermostat, scenes, music.
        case control
        /// "is anyone's light still on upstairs?": answered from a snapshot in the prompt.
        case ask
        /// "every weekday at 7, open the shades": timers, routines, the wake-up light
        /// and adaptive lighting.
        case schedule
        /// "make the background ocean", "save this as Movie Night": the app itself.
        case app
    }

    @ObservationIgnored private var sessions: [Mode: LanguageModelSession] = [:]
    @ObservationIgnored private var turns: [Mode: Int] = [:]
    @ObservationIgnored private var tools: [Mode: [any Tool]] = [:]
    @ObservationIgnored private var snapshot: (() -> String)?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var quick: QuickCommands?
    @ObservationIgnored private var automation: AutomationStore?
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    /// Short, predictable answers are faster answers.
    private static let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 100)
    /// A fresh session every few turns keeps the prompt small, which keeps replies quick.
    private static let turnsPerSession = 4

    func configure(home: HomeStore, music: MusicStore, weather: WeatherStore, settings: AppSettings,
                   automation: AutomationStore, app: AppControl) {
        self.settings = settings
        self.automation = automation
        quick = QuickCommands(home: home, music: music, settings: settings, automation: automation, weather: weather, app: app)
        tools = [
            .control: [
                ControlLightsTool(home: home),
                DeviceTool(home: home),
                ThermostatTool(home: home, settings: settings),
                SceneTool(runner: SceneRunner(home: home, music: music, settings: settings)),
                MusicTool(music: music),
            ],
            .ask: [],
            .schedule: [
                TimerTool(automation: automation),
                RoutineTool(automation: automation),
                ManageAutomationsTool(app: app),
                WakeUpLightTool(app: app),
                AdaptiveLightingTool(app: app),
            ],
            .app: [
                ChangeLookTool(app: app),
                ChangeDashboardTool(app: app),
                NightClockTool(app: app),
                SaveSceneTool(app: app),
                OpenScreenTool(app: app),
            ],
        ]
        snapshot = {
            var status = home.assistantStatus(weather: weather, prefs: settings.prefs) + "\n" + app.summary
            if let scheduled = automation.assistantSummary { status += "\n" + scheduled }
            return status
        }
    }

    /// Loads the model and the instructions ahead of time so the first answer is quick.
    func prewarm() {
        guard unavailableReason == nil else { return }
        // Commands and questions are the most common; the others warm up on first use.
        session(for: .control).prewarm()
        session(for: .ask).prewarm()
    }

    /// Which session a request belongs to. Wrong guesses still work, just less well,
    /// so this errs toward control.
    static func mode(for text: String) -> Mode {
        let text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = { (patterns: [String]) in
            patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
        }
        // Questions first: "when is my alarm?" is answered, not acted on.
        let questionWords: Set<String> = ["what", "what's", "whats", "which", "who", "when", "where", "why", "how",
                                          "is", "are", "was", "were", "will", "would", "should", "do", "does", "did", "tell"]
        let first = text.split(separator: " ").first.map(String.init) ?? ""
        if text.hasSuffix("?") || questionWords.contains(first) { return .ask }
        // Changing or removing timers and routines, the wake-up light, adaptive lighting.
        let automationWords = [
            "\\bwake (?:me|up)\\b", "\\bwake-up\\b", "\\balarm\\b", "\\badaptive\\b",
            "\\b(?:cancel|delete|remove|pause|resume|stop|disable)\\b.*\\b(?:timers?|routines?)\\b",
        ]
        if matches(automationWords) { return .schedule }
        let appWords = [
            "\\btheme\\b", "\\bbackground\\b", "\\bwallpaper\\b", "\\baccent\\b", "\\bfont\\b", "(?<!['’])\\bclock\\b",
            "\\bnight mode\\b", "\\bscreen ?saver\\b", "\\bthe screen\\b", "\\bsettings\\b", "\\bdashboard\\b",
            "\\bcelsius\\b", "\\bfahrenheit\\b", "\\bclick sounds?\\b", "\\b24.hour\\b", "\\bsave\\b",
            "\\bhide\\b", "\\bshow (?:the |all |only |just )", "\\bopen (?:the |my )?(?:settings|automations|routines)\\b",
            "\\banimated weather\\b",
        ]
        if matches(appWords) { return .app }
        let schedule = [
            "\\bevery\\b", "\\bdaily\\b", "\\bweekdays?\\b", "\\bweekends?\\b", "\\btimer\\b", "\\broutine\\b",
            "\\bschedule\\b", "\\bremind", "\\btomorrow\\b", "\\bat (?:sunset|sunrise|noon|midnight|night)\\b",
            "\\bin (?:\\d+|an|a|half an) ?(?:min|mins|minutes?|hours?|hrs?)\\b",
            "\\bat \\d{1,2}(?::\\d{2})? ?(?:am|pm|a\\.m\\.|p\\.m\\.|o.clock)\\b",
        ]
        if matches(schedule) { return .schedule }
        return .control
    }

    func send(_ text: String, spoken: Bool) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        messages.append(Message(fromUser: true, text: text))
        isResponding = true
        defer { isResponding = false }

        #if DEBUG
        let started = ContinuousClock.now
        defer { print("[Assistant] \"\(text)\" took \(ContinuousClock.now - started)") }
        #endif

        // Everyday commands and questions skip the model entirely. "Turn off the kitchen
        // and make it cozy" does the first part instantly and sends the rest on.
        let quickResult = await quick?.run(text) ?? QuickCommands.Result(remainder: text)
        let instant = quickResult.replies.joined(separator: " ")
        guard let remainder = quickResult.remainder else {
            finish(instant, spoken: spoken)
            return
        }

        if let unavailableReason {
            finish(instant.isEmpty ? unavailableReason : "\(instant) \(unavailableReason)", spoken: false)
            return
        }

        // Stream the reply into a bubble so words appear as soon as they're generated.
        let mode = Self.mode(for: remainder)
        let bubble = Message(fromUser: false, text: instant)
        messages.append(bubble)
        let prefix = instant.isEmpty ? "" : instant + " "
        let reply: String
        do {
            reply = try await stream(remainder, mode: mode, into: bubble.id, after: prefix)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            sessions[mode] = nil
            reply = (try? await stream(remainder, mode: mode, into: bubble.id, after: prefix)) ?? "Sorry, something went wrong. Try again."
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            reply = "Sorry, I can't help with that."
        } catch {
            reply = "Sorry, something went wrong. Try again."
        }
        let full = prefix + reply
        update(bubble.id, full)
        if spoken, settings?.prefs.assistantSpeaks == true { speak(full) }

        // Questions carry a fresh snapshot each time, so their session never keeps history.
        turns[mode, default: 0] += 1
        if mode == .ask || turns[mode, default: 0] >= Self.turnsPerSession {
            sessions[mode] = nil
            turns[mode] = 0
        }
        // Get the next session warm while the person reads the answer.
        prewarm()
    }

    /// Carries out a command for a timer or routine, without adding it to the chat.
    func perform(_ command: String) async -> String {
        let quickResult = await quick?.run(command) ?? QuickCommands.Result(remainder: command)
        let instant = quickResult.replies.joined(separator: " ")
        guard let remainder = quickResult.remainder else { return instant }
        guard unavailableReason == nil else { return "Couldn't run “\(command)”: Apple Intelligence isn't available." }
        // A throwaway session, so automations don't mix into the conversation.
        let mode: Mode = switch Self.mode(for: remainder) {
        case .schedule: .schedule
        case .app: .app
        default: .control
        }
        let session = makeSession(mode)
        do {
            let reply = try await session.respond(to: remainder, options: Self.options).content
            return instant.isEmpty ? reply : "\(instant) \(reply)"
        } catch {
            return "Couldn't run “\(command)”."
        }
    }

    func reset() {
        messages = []
        sessions = [:]
        turns = [:]
        synthesizer.stopSpeaking(at: .immediate)
        prewarm()
    }

    /// Updates a reply bubble if it's still there (Clear may have removed it).
    private func update(_ id: UUID, _ text: String) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text = text
    }

    private func finish(_ reply: String, spoken: Bool) {
        messages.append(Message(fromUser: false, text: reply))
        if spoken, settings?.prefs.assistantSpeaks == true { speak(reply) }
    }

    private func stream(_ text: String, mode: Mode, into id: UUID, after prefix: String) async throws -> String {
        let session = session(for: mode)
        // Questions get the home's current state right in the prompt, so no tool call is needed.
        let prompt = mode == .ask ? "Home right now:\n\(snapshot?() ?? "")\n\nQuestion: \(text)" : text
        var latest = ""
        for try await partial in session.streamResponse(to: prompt, options: Self.options) {
            latest = partial.content
            update(id, prefix + latest)
        }
        #if DEBUG
        for entry in session.transcript { print("[Assistant]", entry) }
        #endif
        return latest
    }

    private func session(for mode: Mode) -> LanguageModelSession {
        if let session = sessions[mode] { return session }
        let session = makeSession(mode)
        sessions[mode] = session
        return session
    }

    private func makeSession(_ mode: Mode) -> LanguageModelSession {
        let unit = settings?.prefs.temperatureUnit.symbol ?? "°F"
        let now = Date.now.formatted(date: .abbreviated, time: .shortened)
        let instructions = switch mode {
        case .control:
            """
            You are DankHome, a home assistant. Use the tools to do what's asked. \
            Temperatures are in \(unit). Answer in one short sentence.
            """
        case .ask:
            """
            You are DankHome, a home assistant. Answer the question from the home status \
            in the prompt. Outdoor weather is not indoor temperature. Temperatures are in \(unit). \
            It is \(now). Answer in one or two short sentences.
            """
        case .schedule:
            """
            You are DankHome, a home assistant. For something to do once after a delay, call \
            setTimer. For something that repeats, like every night or on weekdays, call \
            scheduleRoutine. The command is a short instruction like turn off the kitchen lights. \
            Use manageAutomations to cancel timers or change routines, wakeUpLight for wake-up \
            alarms, and adaptiveLighting for lights that follow the sun. \
            It is \(now). Answer in one short sentence.
            """
        case .app:
            """
            You are DankHome, a smart home app. Use the tools to change the app: its look, the \
            dashboard, the night clock, saving the current lights as a scene, or opening a \
            screen. Answer in one short sentence.
            """
        }
        return LanguageModelSession(tools: tools[mode] ?? [], instructions: instructions)
    }

    private func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        synthesizer.speak(utterance)
    }
}
