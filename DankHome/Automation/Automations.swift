//
//  Automations.swift
//  DankHome
//
//  Timers ("turn off the lights in 30 minutes"), routines ("every night at 10, run
//  Good Night"), the wake-up light and adaptive lighting. The schedule math here is
//  plain value code, so it's easy to test; AutomationStore runs it.
//

import Foundation

/// A command to carry out once, later. Commands are plain sentences ("turn off the
/// kitchen") run the same way the assistant runs them.
struct ScheduledCommand: Codable, Identifiable, Equatable {
    var id = UUID()
    var command: String
    var fireDate: Date
}

/// Sunrise and sunset for one day.
struct SunTimes: Equatable {
    var sunrise: Date
    var sunset: Date

    /// 6:30 AM and 6:30 PM, for when there's no forecast to go on.
    static func fallback(for day: Date, calendar: Calendar = .current) -> SunTimes {
        let start = calendar.startOfDay(for: day)
        return SunTimes(sunrise: start.addingTimeInterval(6.5 * 3600), sunset: start.addingTimeInterval(18.5 * 3600))
    }

    /// The same times moved to another day, for days the forecast doesn't cover.
    func moved(to day: Date, calendar: Calendar = .current) -> SunTimes {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: sunrise), to: calendar.startOfDay(for: day)).day ?? 0
        let shift = TimeInterval(days) * 86_400
        return SunTimes(sunrise: sunrise.addingTimeInterval(shift), sunset: sunset.addingTimeInterval(shift))
    }
}

// MARK: - Routines

/// When in the day a routine runs.
enum RoutineTime: Codable, Equatable {
    case clock(hour: Int, minute: Int)
    /// Minutes before (negative) or after (positive) sunrise or sunset.
    case sunrise(offsetMinutes: Int)
    case sunset(offsetMinutes: Int)

    func date(on day: Date, calendar: Calendar = .current, sun: SunTimes) -> Date? {
        switch self {
        case .clock(let hour, let minute):
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        case .sunrise(let offset):
            sun.sunrise.addingTimeInterval(TimeInterval(offset * 60))
        case .sunset(let offset):
            sun.sunset.addingTimeInterval(TimeInterval(offset * 60))
        }
    }

    /// "at 10:00 PM", "at sunset", "30 min before sunrise".
    var text: String {
        switch self {
        case .clock(let hour, let minute):
            let date = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            return "at \(date.formatted(date: .omitted, time: .shortened))"
        case .sunrise(let offset): return Self.offsetText(offset, event: "sunrise")
        case .sunset(let offset): return Self.offsetText(offset, event: "sunset")
        }
    }

    private static func offsetText(_ minutes: Int, event: String) -> String {
        if minutes == 0 { return "at \(event)" }
        return "\(abs(minutes)) min \(minutes < 0 ? "before" : "after") \(event)"
    }
}

/// A command that repeats on a schedule.
struct Routine: Codable, Identifiable, Equatable {
    var id = UUID()
    var command: String
    var time: RoutineTime
    /// Calendar weekdays (1 = Sunday … 7 = Saturday). Empty means every day.
    var days: Set<Int> = []
    var isEnabled = true
    /// When it last ran in the app, so it runs once per occurrence.
    var lastRun: Date?
    /// Set when the routine lives on the home hub as a HomeKit trigger, which runs it
    /// even when DankHome is closed. The app doesn't run those itself.
    var hubTriggerID: UUID?

    static let weekdays: Set<Int> = [2, 3, 4, 5, 6]
    static let weekends: Set<Int> = [1, 7]

    func runs(on day: Date, calendar: Calendar = .current) -> Bool {
        days.isEmpty || days.contains(calendar.component(.weekday, from: day))
    }

    /// The most recent time it was due, at or before `now` (today's or yesterday's).
    func lastDue(atOrBefore now: Date, calendar: Calendar = .current, sun: (Date) -> SunTimes) -> Date? {
        for offset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), runs(on: day, calendar: calendar),
                  let due = time.date(on: day, calendar: calendar, sun: sun(day)), due <= now else { continue }
            return due
        }
        return nil
    }

    /// The next time it's due after `now`, within a week.
    func nextDue(after now: Date, calendar: Calendar = .current, sun: (Date) -> SunTimes) -> Date? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now), runs(on: day, calendar: calendar),
                  let due = time.date(on: day, calendar: calendar, sun: sun(day)), due > now else { continue }
            return due
        }
        return nil
    }

    /// "Every day", "Weekdays", "Mon, Wed, Fri".
    var daysText: String {
        Self.daysText(days)
    }

    static func daysText(_ days: Set<Int>) -> String {
        if days.isEmpty || days.count == 7 { return "Every day" }
        if days == weekdays { return "Weekdays" }
        if days == weekends { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }.joined(separator: ", ")
    }

    /// "Weekdays at 10:00 PM".
    var scheduleText: String { "\(daysText) \(time.text)" }
}

// MARK: - Wake-up light

/// Fades a room's lights up before the alarm time, like sunrise.
struct WakeAlarm: Codable, Equatable {
    var isEnabled = false
    var hour = 7
    var minute = 0
    /// Calendar weekdays; empty means every day.
    var days: Set<Int> = Routine.weekdays
    var fadeMinutes = 20
    /// The room whose lights fade up.
    var room = ""

    static let startKelvin = 2200.0
    static let endKelvin = 4000.0

    /// The wake time on `day`, when the alarm is set for that day.
    func wakeTime(on day: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled, days.isEmpty || days.contains(calendar.component(.weekday, from: day)) else { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
    }

    /// 0 when the fade starts, 1 at the wake time; nil outside the fade (and the few
    /// minutes after it, so a slow tick still lands on full brightness).
    func progress(at now: Date, calendar: Calendar = .current) -> Double? {
        guard let wake = wakeTime(on: now, calendar: calendar) else { return nil }
        let fade = TimeInterval(max(fadeMinutes, 1) * 60)
        let start = wake.addingTimeInterval(-fade)
        guard now >= start, now <= wake.addingTimeInterval(5 * 60) else { return nil }
        return (now.timeIntervalSince(start) / fade).clamped(to: 0...1)
    }
}

// MARK: - Adaptive lighting

/// Cooler, brighter white by day and warm white in the evening, following the sun.
enum CircadianCurve {
    /// How long the morning warm-up and the evening wind-down take.
    static let morningRamp: TimeInterval = 3600
    static let eveningStart: TimeInterval = -3600     // relative to sunset
    static let eveningEnd: TimeInterval = 2 * 3600

    static func kelvin(at date: Date, sun: SunTimes, day: Double, night: Double) -> Double {
        let rise = sun.sunrise
        let windDown = sun.sunset.addingTimeInterval(eveningStart)
        let dark = sun.sunset.addingTimeInterval(eveningEnd)
        if date < rise { return night }
        if date < rise.addingTimeInterval(morningRamp) {
            return night + (day - night) * ease(date.timeIntervalSince(rise) / morningRamp)
        }
        if date < windDown { return day }
        if date < dark {
            return day + (night - day) * ease(date.timeIntervalSince(windDown) / dark.timeIntervalSince(windDown))
        }
        return night
    }

    /// Smooth start and finish.
    private static func ease(_ x: Double) -> Double {
        let x = x.clamped(to: 0...1)
        return x * x * (3 - 2 * x)
    }
}

// MARK: - Timer phrases

enum TimerPhrase {
    /// Splits "turn off the lights in 30 minutes" (or "in 1 hour, lock the front door")
    /// into the command and the delay. Only action phrases count, so questions like
    /// "will it rain in 2 hours" aren't mistaken for timers.
    static func parse(_ text: String) -> (command: String, delay: TimeInterval)? {
        let text = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let amount = "(\\d{1,4}|an|a|one|half an)"
        let unit = "(minutes?|mins?|hours?|hrs?)"
        var command: String?, number: String?, unitWord: String?
        if let g = text.captures("^(.+?),? in \(amount) \(unit)$") {
            (command, number, unitWord) = (g[0], g[1], g[2])
        } else if let g = text.captures("^in \(amount) \(unit),? (.+)$") {
            (command, number, unitWord) = (g[2], g[0], g[1])
        }
        guard let command, let number, let unitWord else { return nil }
        let verbs = ["turn", "switch", "set", "dim", "make", "lock", "close", "shut", "open", "run", "start",
                     "play", "pause", "stop", "put", "brighten", "lights", "light"]
        guard let first = command.split(separator: " ").first, verbs.contains(String(first)) else { return nil }
        let value: Double
        switch number {
        case "a", "an", "one": value = 1
        case "half an": value = 0.5
        default: value = Double(number) ?? 0
        }
        let minutes = unitWord.hasPrefix("h") ? value * 60 : value
        guard minutes >= 1, minutes <= 24 * 60 else { return nil }
        return (command, minutes * 60)
    }
}

extension String {
    /// Capture groups when the whole string matches `pattern`, else nil.
    func captures(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: self).map { String(self[$0]) } ?? ""
        }
    }
}
