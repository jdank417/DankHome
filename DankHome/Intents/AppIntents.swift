//
//  AppIntents.swift
//  DankHome
//
//  Siri, Shortcuts and Spotlight: run a scene button, turn the lights off, or ask
//  the assistant. Each opens DankHome (HomeKit only works with the app open), which
//  on a wall panel is already on screen.
//

import AppIntents
import SwiftUI

/// The app's stores, shared between the UI and intents.
final class AppStores {
    static let shared = AppStores()

    let home = HomeStore()
    let music = MusicStore()
    let settings = AppSettings()
    let weather = WeatherStore()
    let idle = IdleMonitor()
    let assistant = AssistantStore()
    let recorder = SceneRecorder()

    var runner: SceneRunner { SceneRunner(home: home, music: music, settings: settings) }

    private init() {
        assistant.configure(home: home, music: music, weather: weather, settings: settings)
    }

    /// Waits (briefly) for HomeKit to load when the app was just launched by Siri.
    func waitForHome() async {
        for _ in 0..<50 where home.isLoading {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

// MARK: - Scene buttons

struct SceneButtonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    static let defaultQuery = SceneButtonQuery()

    var id: String
    var name: String
    var symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ button: SceneButton) {
        id = button.id.uuidString
        name = button.name
        symbol = button.symbol
    }
}

struct SceneButtonQuery: EntityStringQuery {
    @MainActor
    private func all() async -> [SceneButtonEntity] {
        await AppStores.shared.waitForHome()
        let stores = AppStores.shared
        return stores.settings.sceneButtons(home: stores.home)
            .filter { !$0.name.isEmpty }
            .map(SceneButtonEntity.init)
    }

    func entities(for identifiers: [String]) async throws -> [SceneButtonEntity] {
        await all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [SceneButtonEntity] {
        await all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [SceneButtonEntity] {
        await all()
    }
}

struct RunSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Scene"
    static let description = IntentDescription("Runs one of your DankHome scene buttons.")
    static let openAppWhenRun = true

    @Parameter(title: "Scene")
    var scene: SceneButtonEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stores = AppStores.shared
        await stores.waitForHome()
        guard let button = stores.settings.sceneButtons(home: stores.home).first(where: { $0.id.uuidString == scene.id }) else {
            return .result(dialog: "I couldn't find \(scene.name).")
        }
        stores.runner.run(button)
        return .result(dialog: "Done. \(button.name) is on.")
    }
}

// MARK: - Lights

struct LightsOffIntent: AppIntent {
    static let title: LocalizedStringResource = "Turn Off All Lights"
    static let description = IntentDescription("Turns off every light in the home.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stores = AppStores.shared
        await stores.waitForHome()
        stores.home.selectedRoom = nil
        stores.home.setAllVisible(on: false)
        return .result(dialog: "All the lights are off.")
    }
}

// MARK: - Assistant

struct AskAssistantIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask DankHome"
    static let description = IntentDescription("Ask the DankHome assistant to do something, like “dim the kitchen to 30%”.")
    static let openAppWhenRun = true

    @Parameter(title: "Request", requestValueDialog: "What would you like me to do?")
    var request: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let stores = AppStores.shared
        await stores.waitForHome()
        await stores.assistant.send(request, spoken: false)
        let reply = stores.assistant.messages.last(where: { !$0.fromUser })?.text ?? "Done."
        return .result(dialog: "\(reply)")
    }
}

// MARK: - Siri phrases

struct DankHomeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunSceneIntent(),
            phrases: [
                "Run \(\.$scene) in \(.applicationName)",
                "Turn on \(\.$scene) in \(.applicationName)",
                "\(.applicationName) \(\.$scene)",
                "Run a \(.applicationName) scene",
            ],
            shortTitle: "Run Scene",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: LightsOffIntent(),
            phrases: [
                "Turn off the lights in \(.applicationName)",
                "\(.applicationName) lights off",
            ],
            shortTitle: "All Lights Off",
            systemImageName: "lightbulb.slash"
        )
        AppShortcut(
            intent: AskAssistantIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Tell \(.applicationName)",
            ],
            shortTitle: "Ask DankHome",
            systemImageName: "sparkles.rectangle.stack"
        )
    }
}
