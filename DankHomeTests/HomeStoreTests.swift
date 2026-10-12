//
//  HomeStoreTests.swift
//  DankHomeTests
//
//  Runs against demo mode, so no real accessories are touched.
//

import Foundation
import Testing
@testable import DankHome

@MainActor
struct HomeStoreTests {
    private func demoHome() -> HomeStore {
        let home = HomeStore()
        home.forceDemo = true
        return home
    }

    @Test func turnOffARoom() {
        let home = demoHome()
        let result = home.assistantControlLights(room: "kitchen", light: nil, on: false, brightness: nil, color: nil)
        #expect(result.hasPrefix("Success."))
        #expect(home.lights.filter { $0.roomName == "Kitchen" }.allSatisfy { !$0.isOn })
        // Other rooms are untouched.
        #expect(home.lights.contains { $0.roomName == "Living Room" && $0.isOn })
    }

    @Test func unknownNamesListWhatExists() {
        let home = demoHome()
        let result = home.assistantControlLights(room: "garage attic", light: nil, on: true, brightness: nil, color: nil)
        #expect(result.hasPrefix("No lights matched."))
    }

    @Test func assistantWontUnlockDoors() {
        let home = demoHome()
        let result = home.assistantControlDevice("front door", active: false)
        #expect(result.hasPrefix("For safety"))
        #expect(home.devices.first { $0.name == "Front Door" }?.active == true)
    }

    @Test func biggestPowerDrawComesFirst() {
        let home = demoHome()
        let items = home.poweredItems()
        #expect(items.first?.name == "Space Heater")
        #expect(home.totalWatts == 1480 + 94)
        #expect(home.leftOnDevices(hours: 4).map(\.name) == ["Space Heater"])
    }

    @Test func turningOffForgetsTheTime() throws {
        let home = demoHome()
        let heater = try #require(home.poweredItems().first { $0.name == "Space Heater" })
        #expect(heater.since != nil)
        home.turnOff(heater)
        #expect(home.onSince["Bedroom|Space Heater"] == nil)
        #expect(!home.poweredItems().contains { $0.name == "Space Heater" })
    }

    @Test func quickCommandsSkipTheModel() async {
        let home = demoHome()
        let quick = QuickCommands(home: home, music: MusicStore(), settings: AppSettings())
        let reply = await quick.handle("please turn off the kitchen")
        #expect(reply != nil)
        #expect(home.lights.filter { $0.roomName == "Kitchen" }.allSatisfy { !$0.isOn })
        // Questions go to the model.
        #expect(await quick.handle("why is it so cold") == nil)
    }
}

@MainActor
struct QuickAnswerTests {
    private func setup() -> (HomeStore, QuickCommands) {
        let home = HomeStore()
        home.forceDemo = true
        return (home, QuickCommands(home: home, music: MusicStore(), settings: AppSettings()))
    }

    @Test func lightsInARoom() async {
        let (_, quick) = setup()
        #expect(await quick.handle("Which lights are on in the kitchen?") == "Under Cabinet is on in the Kitchen.")
    }

    @Test func oneLightByName() async {
        let (_, quick) = setup()
        #expect(await quick.handle("Is the porch light on?") == "Porch isn't responding.")
    }

    @Test func locks() async {
        let (_, quick) = setup()
        #expect(await quick.handle("Is the front door locked?") == "Front Door is locked.")
        #expect(await quick.handle("Are the doors locked?") == "Front Door is locked.")
        #expect(await quick.handle("Is the garage open?") == "Garage is closed.")
    }

    @Test func insideTemperature() async throws {
        let (_, quick) = setup()
        let reply = try #require(await quick.handle("What's the temperature inside?"))
        #expect(reply.hasPrefix("It's") && reply.contains("inside") && reply.contains("Heating to"))
    }

    @Test func twoCommandsAtOnce() async {
        let (home, quick) = setup()
        let result = await quick.run("Turn off the kitchen and lock the front door")
        #expect(result.remainder == nil)
        #expect(result.replies.count == 2)
        #expect(home.lights.filter { $0.roomName == "Kitchen" }.allSatisfy { !$0.isOn })
    }

    @Test func leftoverGoesToTheModel() async {
        let (home, quick) = setup()
        let result = await quick.run("turn off the kitchen and then make it cozy in here")
        #expect(result.replies.count == 1)
        #expect(result.remainder == "make it cozy in here")
        #expect(home.lights.filter { $0.roomName == "Kitchen" }.allSatisfy { !$0.isOn })
    }

    @Test func roomNamesWithAndStayWhole() async {
        let (_, quick) = setup()
        // "dining room" doesn't start with a verb, so this isn't split into two commands.
        let result = await quick.run("dim the living and dining room to 20%")
        #expect(result.replies.count <= 1)
        #expect(result.remainder == nil || result.remainder == "dim the living and dining room to 20%")
    }
}

@MainActor
struct AssistantRoutingTests {
    @Test(arguments: [
        ("every night at 10, run Good Night", AssistantStore.Mode.schedule),
        ("dim the bedroom at 9 pm", AssistantStore.Mode.schedule),
        ("turn the porch light off in an hour", AssistantStore.Mode.schedule),
        ("Is anything still on upstairs?", AssistantStore.Mode.ask),
        ("how warm should I keep the nursery", AssistantStore.Mode.ask),
        ("make the living room cozy", AssistantStore.Mode.control),
        ("can you get the house ready for a movie", AssistantStore.Mode.control),
    ])
    func routing(_ text: String, mode: AssistantStore.Mode) {
        #expect(AssistantStore.mode(for: text) == mode)
    }
}
