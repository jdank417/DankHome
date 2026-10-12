//
//  AppTools.swift
//  DankHome
//
//  Tools that let the model change the app itself. They hand their arguments to
//  AppControl on the main actor and return its sentence.
//

import FoundationModels
import SwiftUI

// MARK: - Look and dashboard (app mode)

nonisolated struct ChangeLookTool: Tool {
    let app: AppControl
    let name = "changeLook"
    let description = "Changes how DankHome looks: background theme, accent color, app font, clock font and color, animated weather."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Background: ambient, midnight, aurora, sunset, ocean, forest, graphite or black")
        var background: String?
        @Guide(description: "Accent color name such as cyan, orange or purple")
        var accentColor: String?
        @Guide(description: "App font: classic, rounded, new york or mono")
        var appFont: String?
        @Guide(description: "Clock font: classic, rounded, new york, mono, condensed or wide")
        var clockFont: String?
        @Guide(description: "Clock color name such as white, warm, red or blue")
        var clockColor: String?
        var animatedWeather: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.changeLook(theme: arguments.background, accent: arguments.accentColor, appFont: arguments.appFont,
                             clockFont: arguments.clockFont, clockColor: arguments.clockColor,
                             weatherEffects: arguments.animatedWeather)
    }
}

nonisolated struct ChangeDashboardTool: Tool {
    let app: AppControl
    let name = "changeDashboard"
    let description = "Shows or hides a dashboard section, picks the room shown, sets °F or °C, click sounds, or 24-hour time."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "Section to show or hide: thermostat, weather, music, devices, scenes or date")
        var section: String?
        @Guide(description: "true to show the section, false to hide it")
        var show: Bool?
        @Guide(description: "Room to show on the dashboard, or all")
        var room: String?
        @Guide(description: "fahrenheit or celsius")
        var units: String?
        var clickSounds: Bool?
        var twentyFourHourTime: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.changeDashboard(section: arguments.section, show: arguments.show, room: arguments.room,
                                  units: arguments.units, clickSounds: arguments.clickSounds,
                                  twentyFourHour: arguments.twentyFourHourTime)
    }
}

nonisolated struct NightClockTool: Tool {
    let app: AppControl
    let name = "nightClock"
    let description = "Starts the dim night clock now, turns it on or off, or sets how long the screen waits before it starts."

    @Generable
    nonisolated enum Action {
        case startNow, turnOn, turnOff, unchanged
    }

    @Generable
    nonisolated struct Arguments {
        var action: Action
        @Guide(description: "Minutes without a touch before the night clock starts", .range(1...120))
        var idleMinutes: Int?
        var redAfterMidnight: Bool?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.nightClock(arguments.action, idleMinutes: arguments.idleMinutes,
                             redAfterMidnight: arguments.redAfterMidnight)
    }
}

nonisolated struct SaveSceneTool: Tool {
    let app: AppControl
    let name = "saveScene"
    let description = "Saves the lights as they are right now as a scene button with a name, for one room or the whole home."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The scene's name, such as Movie Night")
        var name: String
        @Guide(description: "A room to save just that room's lights. Empty for the whole home.")
        var room: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.saveScene(name: arguments.name, room: arguments.room)
    }
}

nonisolated struct OpenScreenTool: Tool {
    let app: AppControl
    let name = "openScreen"
    let description = "Opens a screen: what's on (power and things left on), settings, or automations (timers and routines)."

    @Generable
    nonisolated enum Screen {
        case whatsOn, settings, automations
    }

    @Generable
    nonisolated struct Arguments {
        var screen: Screen
    }

    func call(arguments: Arguments) async throws -> String {
        await app.open(arguments.screen)
    }
}

// MARK: - Wake-up light, adaptive lighting, routines (schedule mode)

nonisolated struct WakeUpLightTool: Tool {
    let app: AppControl
    let name = "wakeUpLight"
    let description = "Sets the wake-up light, which fades a room's lights up by the alarm time, or turns it off."

    @Generable
    nonisolated enum Days {
        case everyDay, weekdays, weekends, unchanged
    }

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "false to turn the wake-up light off")
        var on: Bool?
        @Guide(description: "Wake-up hour from 0 to 23, so 6:30 AM is 6", .range(0...23))
        var hour: Int?
        @Guide(description: "Wake-up minute from 0 to 59", .range(0...59))
        var minute: Int?
        @Guide(description: "Room whose lights fade up, such as Bedroom")
        var room: String?
        var days: Days
        @Guide(description: "How many minutes the fade takes", .range(5...90))
        var fadeMinutes: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.wakeUpLight(on: arguments.on, hour: arguments.hour, minute: arguments.minute, room: arguments.room,
                              days: arguments.days.weekdaySet, fadeMinutes: arguments.fadeMinutes)
    }
}

nonisolated extension WakeUpLightTool.Days {
    /// Calendar weekdays (1 = Sunday); nil leaves them as they are.
    var weekdaySet: Set<Int>? {
        switch self {
        case .everyDay: []
        case .weekdays: [2, 3, 4, 5, 6]
        case .weekends: [1, 7]
        case .unchanged: nil
        }
    }
}

nonisolated struct AdaptiveLightingTool: Tool {
    let app: AppControl
    let name = "adaptiveLighting"
    let description = "Turns adaptive lighting on or off (white lights follow the sun), or sets its day and night warmth."

    @Generable
    nonisolated struct Arguments {
        var on: Bool?
        @Guide(description: "Daytime white in Kelvin, 3500 to 6500", .range(3500...6500))
        var daytimeKelvin: Int?
        @Guide(description: "Night white in Kelvin, 2000 to 3000", .range(2000...3000))
        var nightKelvin: Int?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.adaptiveLighting(on: arguments.on, daytimeKelvin: arguments.daytimeKelvin, nightKelvin: arguments.nightKelvin)
    }
}

nonisolated struct ManageAutomationsTool: Tool {
    let app: AppControl
    let name = "manageAutomations"
    let description = "Cancels all timers, or deletes, pauses or resumes a routine by what it does."

    @Generable
    nonisolated enum Action {
        case cancelTimers, deleteRoutine, pauseRoutine, resumeRoutine
    }

    @Generable
    nonisolated struct Arguments {
        var action: Action
        @Guide(description: "Words from the routine, such as Good Night or shades")
        var routine: String?
    }

    func call(arguments: Arguments) async throws -> String {
        await app.manageAutomations(arguments.action, routine: arguments.routine)
    }
}

// MARK: - Main-actor side

/// The tools' choices, turned into app actions on the main actor.
extension AppControl {
    func nightClock(_ action: NightClockTool.Action, idleMinutes: Int?, redAfterMidnight: Bool?) -> String {
        let mapped: NightClockAction? = switch action {
        case .startNow: .startNow
        case .turnOn: .turnOn
        case .turnOff: .turnOff
        case .unchanged: nil
        }
        return nightClock(mapped, idleMinutes: idleMinutes, redAfterMidnight: redAfterMidnight)
    }

    func open(_ screen: OpenScreenTool.Screen) -> String {
        switch screen {
        case .whatsOn: open(AppNavigator.Screen.whatsOn)
        case .settings: open(AppNavigator.Screen.settings)
        case .automations: open(AppNavigator.Screen.automations)
        }
    }

    func manageAutomations(_ action: ManageAutomationsTool.Action, routine: String?) -> String {
        let mapped: AutomationAction = switch action {
        case .cancelTimers: .cancelTimers
        case .deleteRoutine: .deleteRoutine
        case .pauseRoutine: .pauseRoutine
        case .resumeRoutine: .resumeRoutine
        }
        return manageAutomations(mapped, routine: routine)
    }
}
