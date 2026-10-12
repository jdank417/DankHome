//
//  DankHomeTests.swift
//  DankHomeTests
//
//  Created by Jason Dank on 10/8/26.
//

import Foundation
import SwiftUI
import Testing
@testable import DankHome

/// A fixed calendar so date math doesn't depend on where the tests run.
let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// A UTC date. October 12, 2026 is a Monday.
func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

@MainActor
struct FormattingTests {
    @Test func temperatures() {
        var prefs = Preferences()
        prefs.temperatureUnit = .fahrenheit
        #expect(prefs.formatTemperature(celsius: 21) == "70°")
        #expect(prefs.formatTemperature(celsius: nil) == "--°")
        prefs.temperatureUnit = .celsius
        #expect(prefs.formatTemperature(celsius: 21.4) == "21°")
    }

    @Test func durations() {
        #expect(EnergyFormat.duration(20) == "just now")
        #expect(EnergyFormat.duration(45 * 60) == "45 min")
        #expect(EnergyFormat.duration(2 * 3600) == "2 hr")
        #expect(EnergyFormat.duration(6 * 3600 + 12 * 60) == "6 hr 12 min")
        #expect(EnergyFormat.duration(11 * 3600 + 30 * 60) == "11 hr")
        #expect(EnergyFormat.duration(3 * 86_400) == "3 days")
        #expect(EnergyFormat.duration(-60) == "just now")
    }

    @Test func watts() {
        #expect(EnergyFormat.watts(8.4) == "8 W")
        #expect(EnergyFormat.watts(1480) == "1.5 kW")
    }

    @Test func clamping() {
        #expect(150.clamped(to: 0...100) == 100)
        #expect((-3.0).clamped(to: 0...1) == 0)
        #expect(0.5.clamped(to: 0...1) == 0.5)
    }
}

@MainActor
struct LayoutTests {
    @Test func savedOrderComesFirst() {
        let sorted = GridReorder.sorted(["a", "b", "c", "d"], by: ["c", "a"], key: { $0 })
        #expect(sorted == ["c", "a", "b", "d"])
    }

    @Test func unknownSavedKeysAreIgnored() {
        let sorted = GridReorder.sorted(["a", "b"], by: ["gone", "b"], key: { $0 })
        #expect(sorted == ["b", "a"])
    }

    @Test func lightGridPicksTheLargestTiles() {
        // A wide, short area fits four lights side by side better than two rows of two.
        #expect(LightsGrid.fit(count: 4, in: CGSize(width: 800, height: 200), spacing: 12).columns == 4)
        // A tall, narrow area stacks them.
        #expect(LightsGrid.fit(count: 4, in: CGSize(width: 200, height: 800), spacing: 12).columns == 1)
        let empty = LightsGrid.fit(count: 0, in: CGSize(width: 200, height: 200), spacing: 12)
        #expect(empty.columns == 1 && empty.height == 1)
    }
}

@MainActor
struct SettingsTests {
    @Test func savedSettingsKeepNewDefaults() throws {
        // Saved by an older version that only knew about a couple of settings.
        let data = Data(#"{"use24Hour": true, "nightIdleMinutes": 15}"#.utf8)
        let prefs = try #require(AppSettings.decode(data))
        #expect(prefs.use24Hour)
        #expect(prefs.nightIdleMinutes == 15)
        #expect(prefs.leftOnWarningHours == Preferences().leftOnWarningHours)
        #expect(prefs.wakeAlarm == WakeAlarm())
    }

    @Test func roundTrip() throws {
        var prefs = Preferences()
        prefs.adaptiveLighting = true
        prefs.wakeAlarm.room = "Bedroom"
        prefs.wakeAlarm.days = [1, 7]
        let data = try JSONEncoder().encode(prefs)
        let decoded = try #require(AppSettings.decode(data))
        #expect(decoded.adaptiveLighting)
        #expect(decoded.wakeAlarm == prefs.wakeAlarm)
    }

    @Test func garbageIsRejected() {
        #expect(AppSettings.decode(Data("not json".utf8)) == nil)
    }
}

@MainActor
struct DeviceTests {
    private func device(_ kind: Device.Kind, active: Bool, level: Double? = nil) -> Device {
        Device(id: UUID(), name: "Thing", roomName: "Room", kind: kind, active: active, level: level, isReachable: true)
    }

    @Test func statusText() {
        #expect(device(.lock, active: true).status == "Locked")
        #expect(device(.garage, active: true).status == "Open")
        #expect(device(.shade, active: true, level: 40).status == "40% Open")
        #expect(device(.shade, active: false, level: 0).status == "Closed")
        #expect(device(.fan, active: true, level: 60).status == "60%")
        var offline = device(.outlet, active: true)
        offline.isReachable = false
        #expect(offline.status == "No Response")
    }

    @Test func unlockingAndOpeningTheGarageAskFirst() {
        #expect(device(.lock, active: true).needsConfirmation)    // tapping unlocks
        #expect(!device(.lock, active: false).needsConfirmation)  // tapping locks
        #expect(device(.garage, active: false).needsConfirmation) // tapping opens
        #expect(!device(.garage, active: true).needsConfirmation)
    }

    @Test func leftOnWarnings() {
        let now = date(2026, 10, 12, 20)
        let heater = PoweredItem(id: UUID(), key: "Bedroom|Heater", name: "Heater", roomName: "Bedroom",
                                 source: .device(.outlet), symbol: "", tint: .orange, watts: 1500,
                                 since: now.addingTimeInterval(-5 * 3600))
        #expect(heater.isLeftOn(now: now, hours: 4))
        #expect(!heater.isLeftOn(now: now, hours: 8))
        #expect(!heater.isLeftOn(now: now, hours: 0))  // warnings off
        var lamp = heater
        lamp.source = .light
        #expect(!lamp.isLeftOn(now: now, hours: 4))    // lights are never flagged
    }
}
