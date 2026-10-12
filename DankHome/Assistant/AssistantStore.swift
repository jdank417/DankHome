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
            list = ["Will it rain this afternoon?", "Set the thermostat to 70", "Which lights are on?"]
        case 17..<21:
            list = ["Make the living room warm white at 40%", "Close the shades", "Will it be cold tonight?"]
            if let evening = scene(["movie", "relax", "dinner"]) { list.insert("Run \(evening)", at: 0) }
        default:
            list = ["Turn off all the lights", "Lock the front door", "Set the thermostat to 66"]
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
        case .unavailable(.deviceNotEligible): "This iPad doesn't support Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri."
        case .unavailable(.modelNotReady): "Apple Intelligence is still downloading. Try again in a few minutes."
        case .unavailable: "Apple Intelligence isn't available right now."
        }
    }

    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private var tools: [any Tool] = []
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var quick: QuickCommands?
    @ObservationIgnored private var automation: AutomationStore?
    @ObservationIgnored private var turns = 0
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

    /// Short answers are faster answers.
    private static let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 120)
    /// A fresh session every few turns keeps the prompt small, which keeps replies quick.
    private static let turnsPerSession = 4

    func configure(home: HomeStore, music: MusicStore, weather: WeatherStore, settings: AppSettings,
                   automation: AutomationStore) {
        self.settings = settings
        self.automation = automation
        quick = QuickCommands(home: home, music: music, settings: settings, automation: automation)
        tools = [
            ControlLightsTool(home: home),
            DeviceTool(home: home),
            ThermostatTool(home: home, settings: settings),
            SceneTool(runner: SceneRunner(home: home, music: music, settings: settings)),
            MusicTool(music: music),
            TimerTool(automation: automation),
            RoutineTool(automation: automation),
            HomeStatusTool(home: home, weather: weather, settings: settings, automation: automation),
        ]
    }

    /// Loads the model and the instructions ahead of time so the first answer is quick.
    func prewarm() {
        guard unavailableReason == nil else { return }
        makeSessionIfNeeded().prewarm()
    }

    func send(_ text: String, spoken: Bool) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }
        messages.append(Message(fromUser: true, text: text))
        isResponding = true
        defer { isResponding = false }

        // Everyday commands skip the model entirely.
        if let reply = await quick?.handle(text) {
            finish(reply, spoken: spoken)
            return
        }

        if let unavailableReason {
            finish(unavailableReason, spoken: false)
            return
        }

        // Stream the reply into a bubble so words appear as soon as they're generated.
        let bubble = Message(fromUser: false, text: "")
        messages.append(bubble)
        let reply: String
        do {
            reply = try await stream(text, into: bubble.id)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            session = nil
            reply = (try? await stream(text, into: bubble.id)) ?? "Sorry, something went wrong. Try again."
        } catch LanguageModelSession.GenerationError.guardrailViolation {
            reply = "Sorry, I can't help with that."
        } catch {
            reply = "Sorry, something went wrong. Try again."
        }
        update(bubble.id, reply)
        if spoken, settings?.prefs.assistantSpeaks == true { speak(reply) }

        turns += 1
        if turns >= Self.turnsPerSession {
            session = nil
            turns = 0
        }
        // Get the next session warm while the person reads the answer.
        prewarm()
    }

    /// Carries out a command for a timer or routine, without adding it to the chat.
    func perform(_ command: String) async -> String {
        if let reply = await quick?.handle(command) { return reply }
        guard unavailableReason == nil else { return "Couldn't run “\(command)”: Apple Intelligence isn't available." }
        let session = LanguageModelSession(tools: tools, instructions: """
            You are DankHome, a home assistant. Carry out the request now using the tools. \
            Answer in one short sentence.
            """)
        do {
            return try await session.respond(to: command, options: Self.options).content
        } catch {
            return "Couldn't run “\(command)”."
        }
    }

    func reset() {
        messages = []
        session = nil
        turns = 0
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

    private func stream(_ text: String, into id: UUID) async throws -> String {
        let session = makeSessionIfNeeded()
        var latest = ""
        for try await snapshot in session.streamResponse(to: text, options: Self.options) {
            latest = snapshot.content
            update(id, latest)
        }
        #if DEBUG
        for entry in session.transcript { print("[Assistant]", entry) }
        #endif
        return latest
    }

    private func makeSessionIfNeeded() -> LanguageModelSession {
        if let session { return session }
        let unit = settings?.prefs.temperatureUnit.symbol ?? "°F"
        let session = LanguageModelSession(tools: tools, instructions: """
            You are DankHome, a home assistant. Use the tools to act. \
            Call getHomeStatus for questions about the home, weather or music. \
            For requests to do something later or after a delay, call setTimer. \
            For requests that repeat, like every night or every weekday, call scheduleRoutine. \
            Temperatures are in \(unit). It is \(Date.now.formatted(date: .abbreviated, time: .shortened)). \
            Answer in one short sentence.
            """)
        self.session = session
        return session
    }

    private func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        synthesizer.speak(utterance)
    }
}
