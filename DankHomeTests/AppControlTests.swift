//
//  AppControlTests.swift
//  DankHomeTests
//
//  The assistant changing the app itself, through the instant phrases. Runs on
//  the demo home with settings that are never saved.
//

import Foundation
import Testing
@testable import DankHome

@MainActor
struct AppControlTests {
    private struct Fixture {
        let home: HomeStore
        let settings: AppSettings
        let navigator: AppNavigator
        let quick: QuickCommands
    }

    private func fixture() -> Fixture {
        let home = HomeStore()
        home.forceDemo = true
        let settings = AppSettings(persists: false)
        let automation = AutomationStore(persists: false)
        let navigator = AppNavigator()
        let app = AppControl(home: home, settings: settings, automation: automation, idle: IdleMonitor(), navigator: navigator)
        let quick = QuickCommands(home: home, music: MusicStore(), settings: settings, automation: automation, app: app)
        return Fixture(home: home, settings: settings, navigator: navigator, quick: quick)
    }

    @Test func saveTheWholeHome() async throws {
        let f = fixture()
        let reply = try #require(await f.quick.handle("Save this as movie night"))
        #expect(reply.hasPrefix("Saved Movie Night"))
        let button = try #require(f.settings.sceneButtons(home: f.home).first { $0.name == "Movie Night" })
        #expect(button.symbol == "tv.fill")
        guard case .custom(let scene) = button.action else { Issue.record("Expected a custom scene"); return }
        #expect(scene.lights.count == f.home.lights.filter(\.isReachable).count)
        #expect(scene.thermostat != nil)
    }

    @Test func saveOneRoom() async throws {
        let f = fixture()
        _ = await f.quick.handle("save the kitchen as dinner")
        let button = try #require(f.settings.sceneButtons(home: f.home).first { $0.name == "Dinner" })
        guard case .custom(let scene) = button.action else { Issue.record("Expected a custom scene"); return }
        #expect(scene.lights.allSatisfy { $0.key.hasPrefix("Kitchen|") })
        #expect(scene.thermostat == nil)
    }

    @Test func savingAgainReplaces() async {
        let f = fixture()
        _ = await f.quick.handle("save this as reading")
        let reply = await f.quick.handle("save this as Reading")
        #expect(reply?.hasPrefix("Updated Reading") == true)
        #expect(f.settings.sceneButtons(home: f.home).filter { $0.name == "Reading" }.count == 1)
    }

    @Test func wakeUpLight() async {
        let f = fixture()
        _ = await f.quick.handle("Wake me up at 6:30 am on weekdays")
        let alarm = f.settings.prefs.wakeAlarm
        #expect(alarm.isEnabled)
        #expect(alarm.hour == 6 && alarm.minute == 30)
        #expect(alarm.days == Routine.weekdays)
        #expect(alarm.room == "Bedroom")

        _ = await f.quick.handle("wake me up at 7 pm")
        #expect(f.settings.prefs.wakeAlarm.hour == 19)

        _ = await f.quick.handle("turn off the wake up light")
        #expect(!f.settings.prefs.wakeAlarm.isEnabled)
    }

    @Test func settings() async {
        let f = fixture()
        _ = await f.quick.handle("switch to celsius")
        #expect(f.settings.prefs.temperatureUnit == .celsius)
        _ = await f.quick.handle("turn on adaptive lighting")
        #expect(f.settings.prefs.adaptiveLighting)
        _ = await f.quick.handle("switch to the ocean background")
        #expect(f.settings.prefs.theme == .ocean)
    }

    @Test func showARoom() async {
        let f = fixture()
        defer { f.home.selectedRoom = nil }
        _ = await f.quick.handle("go to the living room")
        #expect(f.home.selectedRoom == "Living Room")
        _ = await f.quick.handle("show all rooms")
        #expect(f.home.selectedRoom == nil)
    }

    @Test func openScreens() async {
        let f = fixture()
        _ = await f.quick.handle("Show what's on")
        #expect(f.navigator.request == .whatsOn)
        _ = await f.quick.handle("open my routines")
        #expect(f.navigator.request == .automations)
    }

    @Test func shadeLevel() async {
        let f = fixture()
        let reply = await f.quick.handle("set the shades to 40%")
        #expect(reply == "Shades set to 40% open.")
        #expect(f.home.devices.first { $0.name == "Shades" }?.level == 40)
    }

    @Test func thermostatStillWorks() async {
        // "set the thermostat to 70" mustn't be mistaken for a shade or fan level.
        let f = fixture()
        let reply = await f.quick.handle("set the thermostat to 70")
        #expect(reply?.hasPrefix("Thermostat is") == true)
    }

    @Test(arguments: [
        ("switch to the ocean background", AssistantStore.Mode.app),
        ("hide the weather", AssistantStore.Mode.app),
        ("save this as Movie Night", AssistantStore.Mode.app),
        ("make the clock red", AssistantStore.Mode.app),
        ("cancel the bedtime routine", AssistantStore.Mode.schedule),
        ("wake me up gently at 7", AssistantStore.Mode.schedule),
        ("When is my alarm?", AssistantStore.Mode.ask),
        ("dim the lights at 9 o'clock", AssistantStore.Mode.schedule),
    ])
    func routing(_ text: String, mode: AssistantStore.Mode) {
        #expect(AssistantStore.mode(for: text) == mode)
    }
}
