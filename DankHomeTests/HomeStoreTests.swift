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
