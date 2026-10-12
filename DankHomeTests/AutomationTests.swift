//
//  AutomationTests.swift
//  DankHomeTests
//

import Foundation
import Testing
@testable import DankHome

@MainActor
struct TimerPhraseTests {
    @Test func delayAtTheEnd() throws {
        let timer = try #require(TimerPhrase.parse("Turn off the lights in 30 minutes."))
        #expect(timer.command == "turn off the lights")
        #expect(timer.delay == 30 * 60)
    }

    @Test func delayAtTheStart() throws {
        let timer = try #require(TimerPhrase.parse("in an hour, lock the front door"))
        #expect(timer.command == "lock the front door")
        #expect(timer.delay == 3600)
    }

    @Test(arguments: [
        ("in half an hour turn off the tv", 30.0),
        ("dim the kitchen to 20% in 2 hrs", 120.0),
        ("close the shades in 1 min", 1.0),
    ])
    func wordings(_ text: String, minutes: Double) throws {
        #expect(try #require(TimerPhrase.parse(text)).delay == minutes * 60)
    }

    @Test(arguments: [
        "will it rain in 2 hours",       // a question, not a timer
        "turn off the lights",           // no delay
        "turn off the lights in 0 minutes",
        "turn off the lights in 3000 hours",
    ])
    func notTimers(_ text: String) {
        #expect(TimerPhrase.parse(text) == nil)
    }
}

@MainActor
struct RoutineTests {
    /// Sunrise at 6:00 and sunset at 18:00 every day.
    private func sun(_ day: Date) -> SunTimes {
        let start = utc.startOfDay(for: day)
        return SunTimes(sunrise: start.addingTimeInterval(6 * 3600), sunset: start.addingTimeInterval(18 * 3600))
    }

    @Test func everyNight() {
        let routine = Routine(command: "run Good Night", time: .clock(hour: 22, minute: 0))
        // Monday 11 PM: tonight's 10 PM has passed.
        #expect(routine.lastDue(atOrBefore: date(2026, 10, 12, 23), calendar: utc, sun: sun) == date(2026, 10, 12, 22))
        // Monday 9 PM: the last one was Sunday night; the next is in an hour.
        #expect(routine.lastDue(atOrBefore: date(2026, 10, 12, 21), calendar: utc, sun: sun) == date(2026, 10, 11, 22))
        #expect(routine.nextDue(after: date(2026, 10, 12, 21), calendar: utc, sun: sun) == date(2026, 10, 12, 22))
    }

    @Test func weekdaysSkipTheWeekend() {
        let routine = Routine(command: "open the shades", time: .clock(hour: 7, minute: 0), days: Routine.weekdays)
        let saturday = date(2026, 10, 17, 8)
        // Saturday morning: Friday's run was the last one (within the one-day lookback).
        #expect(routine.lastDue(atOrBefore: saturday, calendar: utc, sun: sun) == date(2026, 10, 16, 7))
        // And the next is Monday.
        #expect(routine.nextDue(after: saturday, calendar: utc, sun: sun) == date(2026, 10, 19, 7))
    }

    @Test func sunsetOffset() {
        let routine = Routine(command: "close the shades", time: .sunset(offsetMinutes: -30))
        #expect(routine.nextDue(after: date(2026, 10, 12, 12), calendar: utc, sun: sun) == date(2026, 10, 12, 17, 30))
    }

    @Test func descriptions() {
        #expect(Routine.daysText([]) == "Every day")
        #expect(Routine.daysText(Set(1...7)) == "Every day")
        #expect(Routine.daysText(Routine.weekdays) == "Weekdays")
        #expect(Routine.daysText(Routine.weekends) == "Weekends")
        #expect(RoutineTime.sunset(offsetMinutes: 0).text == "at sunset")
        #expect(RoutineTime.sunrise(offsetMinutes: -30).text == "30 min before sunrise")
        #expect(RoutineTime.sunset(offsetMinutes: 15).text == "15 min after sunset")
    }

    @Test func routinesSurviveSaving() throws {
        let routine = Routine(command: "run Movie", time: .sunset(offsetMinutes: 10), days: [2, 4])
        let data = try JSONEncoder().encode(routine)
        #expect(try JSONDecoder().decode(Routine.self, from: data) == routine)
    }
}

@MainActor
struct WakeAlarmTests {
    private var alarm: WakeAlarm {
        var alarm = WakeAlarm()
        alarm.isEnabled = true
        alarm.hour = 7
        alarm.minute = 0
        alarm.fadeMinutes = 20
        alarm.days = Routine.weekdays
        alarm.room = "Bedroom"
        return alarm
    }

    @Test func fadesUpToTheWakeTime() {
        // Monday.
        #expect(alarm.progress(at: date(2026, 10, 12, 6, 30), calendar: utc) == nil)
        #expect(alarm.progress(at: date(2026, 10, 12, 6, 40), calendar: utc) == 0)
        #expect(alarm.progress(at: date(2026, 10, 12, 6, 50), calendar: utc) == 0.5)
        #expect(alarm.progress(at: date(2026, 10, 12, 7, 0), calendar: utc) == 1)
        #expect(alarm.progress(at: date(2026, 10, 12, 7, 4), calendar: utc) == 1)
        #expect(alarm.progress(at: date(2026, 10, 12, 7, 10), calendar: utc) == nil)
    }

    @Test func offDaysAndDisabled() {
        // Saturday isn't a weekday.
        #expect(alarm.progress(at: date(2026, 10, 17, 6, 50), calendar: utc) == nil)
        var off = alarm
        off.isEnabled = false
        #expect(off.progress(at: date(2026, 10, 12, 6, 50), calendar: utc) == nil)
    }
}

@MainActor
struct CircadianTests {
    private let sun = SunTimes(sunrise: date(2026, 10, 12, 6), sunset: date(2026, 10, 12, 18))

    private func kelvin(_ hour: Int, _ minute: Int = 0) -> Double {
        CircadianCurve.kelvin(at: date(2026, 10, 12, hour, minute), sun: sun, day: 4500, night: 2200)
    }

    @Test func followsTheSun() {
        #expect(kelvin(3) == 2200)        // night
        #expect(kelvin(12) == 4500)       // day
        #expect(kelvin(17) == 4500)       // wind-down starts an hour before sunset
        #expect(kelvin(23) == 2200)       // two hours after sunset it's fully warm
    }

    @Test func rampsSmoothly() {
        let morning = kelvin(6, 30)
        #expect(morning > 2200 && morning < 4500)
        let evening = [kelvin(17, 30), kelvin(18, 30), kelvin(19, 30)]
        #expect(evening == evening.sorted(by: >))
        #expect(evening.allSatisfy { $0 > 2200 && $0 < 4500 })
    }

    @Test func sunTimesMoveToOtherDays() {
        let moved = sun.moved(to: date(2026, 10, 15, 9), calendar: utc)
        #expect(moved.sunrise == date(2026, 10, 15, 6))
        #expect(moved.sunset == date(2026, 10, 15, 18))
    }
}
