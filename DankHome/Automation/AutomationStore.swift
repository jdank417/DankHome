//
//  AutomationStore.swift
//  DankHome
//
//  Keeps timers and routines, and runs everything time-based from one tick every
//  few seconds: timers, routines, the wake-up light and adaptive lighting.
//
//  Routines that run a Home app scene are also put on the home hub as HomeKit
//  triggers, so they happen even when DankHome is closed. Everything else runs
//  while the app is open, which on a wall-mounted iPad is all the time.
//

import Foundation
import Observation

@Observable
final class AutomationStore {
    private(set) var timers: [ScheduledCommand] = [] {
        didSet { save() }
    }
    private(set) var routines: [Routine] = [] {
        didSet { save() }
    }
    /// A short note about the last automation that ran, for the status line.
    private(set) var lastRunNote: String?

    @ObservationIgnored private var home: HomeStore?
    @ObservationIgnored private var settings: AppSettings?
    @ObservationIgnored private var weather: WeatherStore?
    /// Runs a command the way the assistant would, without adding it to the chat.
    @ObservationIgnored private var perform: ((String) async -> String)?

    @ObservationIgnored private var lastAdaptive = Date.distantPast
    @ObservationIgnored private var alarmDay: Date?
    @ObservationIgnored private var alarmCancelled = false
    @ObservationIgnored private var alarmLevel: Double?
    @ObservationIgnored private var noteTask: Task<Void, Never>?

    private static let key = "automations.v1"
    /// A timer whose time passed while the app was closed still runs if it's this late, at most.
    private static let timerGrace: TimeInterval = 60 * 60
    /// Same for a routine missed while the app was closed.
    private static let routineGrace: TimeInterval = 10 * 60

    private struct Saved: Codable {
        var timers: [ScheduledCommand]
        var routines: [Routine]
    }

    /// Off for tests, so they never touch saved timers and routines.
    private let persists: Bool

    init(persists: Bool = true) {
        self.persists = persists
        if persists, let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            timers = saved.timers
            routines = saved.routines
        }
    }

    func configure(home: HomeStore, settings: AppSettings, weather: WeatherStore, perform: @escaping (String) async -> String) {
        self.home = home
        self.settings = settings
        self.weather = weather
        self.perform = perform
    }

    private func save() {
        guard persists else { return }
        if let data = try? JSONEncoder().encode(Saved(timers: timers, routines: routines)) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: - Timers

    @discardableResult
    func addTimer(_ command: String, after delay: TimeInterval, now: Date = .now) -> ScheduledCommand {
        let timer = ScheduledCommand(command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                                     fireDate: now.addingTimeInterval(delay))
        timers.append(timer)
        timers.sort { $0.fireDate < $1.fireDate }
        return timer
    }

    func cancelTimer(_ id: UUID) {
        timers.removeAll { $0.id == id }
    }

    func cancelAllTimers() {
        timers = []
    }

    // MARK: - Routines

    /// Adds or replaces a routine, then puts it on the home hub when it can live there.
    func save(_ routine: Routine) {
        if let index = routines.firstIndex(where: { $0.id == routine.id }) {
            routines[index] = routine
        } else {
            routines.append(routine)
        }
        Task { await syncHub(routine.id) }
    }

    func remove(_ routine: Routine) {
        routines.removeAll { $0.id == routine.id }
        if let trigger = routine.hubTriggerID {
            Task { await home?.removeHubTrigger(trigger) }
        }
    }

    func setEnabled(_ enabled: Bool, for id: UUID) {
        guard var routine = routines.first(where: { $0.id == id }) else { return }
        routine.isEnabled = enabled
        save(routine)
    }

    /// Runs a routine's command right away.
    func runNow(_ routine: Routine) async -> String {
        await perform?(routine.command) ?? "Not ready yet."
    }

    /// The Home app scene a command runs ("run Good Night"), when that's all it does.
    /// Those routines can live on the home hub.
    func hubSceneName(for command: String) -> String? {
        guard let home, let settings,
              let groups = command.trimmingCharacters(in: .whitespacesAndNewlines)
                .captures("^(?:run|start|activate|turn on) (?:the )?(.+?)(?: scene)?$") else { return nil }
        let wanted = groups[0].lowercased()
        if let button = settings.sceneButtons(home: home).first(where: { $0.name.lowercased() == wanted }) {
            if case .homeScene(let name) = button.action, home.scenes.contains(where: { $0.name == name }) { return name }
            return nil
        }
        return home.scenes.first { $0.name.lowercased() == wanted }?.name
    }

    /// Replaces the routine's hub trigger to match its current settings.
    private func syncHub(_ id: UUID) async {
        guard let home, let routine = routines.first(where: { $0.id == id }) else { return }
        if let old = routine.hubTriggerID {
            await home.removeHubTrigger(old)
        }
        var trigger: UUID?
        if routine.isEnabled, let scene = hubSceneName(for: routine.command) {
            trigger = try? await home.addHubTrigger(name: "DankHome \(scene) \(routine.id.uuidString.prefix(4))",
                                                    sceneName: scene, time: routine.time, days: routine.days)
        }
        // The routine may have been edited or deleted while HomeKit was busy.
        guard let index = routines.firstIndex(where: { $0.id == id }) else {
            if let trigger { await home.removeHubTrigger(trigger) }
            return
        }
        routines[index].hubTriggerID = trigger
    }

    // MARK: - Sun

    /// Sunrise and sunset for a day, from the forecast when it covers that day.
    func sunTimes(for day: Date) -> SunTimes {
        let known = weather?.sunTimes ?? []
        if let exact = known.first(where: { Calendar.current.isDate($0.sunrise, inSameDayAs: day) }) { return exact }
        return known.first?.moved(to: day) ?? .fallback(for: day)
    }

    // MARK: - Tick

    /// Called every few seconds while the app is open.
    func tick(now: Date = .now) async {
        await runTimers(now: now)
        await runRoutines(now: now)
        runWakeAlarm(now: now)
        runAdaptiveLighting(now: now)
    }

    private func runTimers(now: Date) async {
        let due = timers.filter { $0.fireDate <= now }
        guard !due.isEmpty else { return }
        timers.removeAll { $0.fireDate <= now }
        for timer in due where now.timeIntervalSince(timer.fireDate) < Self.timerGrace {
            let result = await perform?(timer.command) ?? ""
            note("Timer: \(result)")
        }
    }

    private func runRoutines(now: Date) async {
        for routine in routines where routine.isEnabled && routine.hubTriggerID == nil {
            guard let due = routine.lastDue(atOrBefore: now, sun: sunTimes(for:)),
                  now.timeIntervalSince(due) < Self.routineGrace,
                  (routine.lastRun ?? .distantPast) < due,
                  let index = routines.firstIndex(where: { $0.id == routine.id }) else { continue }
            routines[index].lastRun = now
            let result = await perform?(routine.command) ?? ""
            note(result)
        }
    }

    private func note(_ text: String) {
        lastRunNote = text
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            lastRunNote = nil
        }
    }

    // MARK: Wake-up light

    /// The room being faded up right now, if any.
    private func wakeRoom(now: Date) -> String? {
        guard let alarm = settings?.prefs.wakeAlarm, !alarm.room.isEmpty, alarm.progress(at: now) != nil,
              !alarmCancelled else { return nil }
        return alarm.room
    }

    private func runWakeAlarm(now: Date) {
        guard let home, let alarm = settings?.prefs.wakeAlarm, !alarm.room.isEmpty,
              let progress = alarm.progress(at: now) else { return }
        let today = Calendar.current.startOfDay(for: now)
        if alarmDay != today {
            alarmDay = today
            alarmCancelled = false
            alarmLevel = nil
        }
        guard !alarmCancelled else { return }
        let lights = home.lights.filter { $0.roomName == alarm.room && $0.isReachable }
        guard !lights.isEmpty else { return }
        // Someone turned them off mid-fade: they're awake, or want to sleep in.
        if alarmLevel != nil, lights.allSatisfy({ !$0.isOn }) {
            alarmCancelled = true
            return
        }
        let level = (1 + 99 * progress).rounded()
        guard level != alarmLevel else { return }
        let kelvin = WakeAlarm.startKelvin + (WakeAlarm.endKelvin - WakeAlarm.startKelvin) * progress
        for light in lights {
            if light.colorTemperature != nil { home.adaptWhite(kelvin: kelvin, for: light.id) }
            if light.brightness != nil {
                home.setBrightness(level, for: light.id, commit: true)
            } else if !light.isOn {
                home.setPower(true, for: light.id)
            }
        }
        alarmLevel = level
    }

    // MARK: Adaptive lighting

    /// The white temperature adaptive lighting wants right now.
    func adaptiveKelvin(now: Date = .now) -> Double? {
        guard let prefs = settings?.prefs else { return nil }
        return CircadianCurve.kelvin(at: now, sun: sunTimes(for: now),
                                     day: prefs.adaptiveDayKelvin, night: prefs.adaptiveNightKelvin)
    }

    private func runAdaptiveLighting(now: Date) {
        guard let home, let prefs = settings?.prefs, prefs.adaptiveLighting,
              now.timeIntervalSince(lastAdaptive) >= 20, let kelvin = adaptiveKelvin(now: now) else { return }
        lastAdaptive = now
        let wakeRoom = wakeRoom(now: now)
        for light in home.lights where light.isOn && light.isReachable && light.usesWhite {
            guard let mireds = light.colorTemperature,
                  prefs.adaptiveLights.isEmpty || prefs.adaptiveLights.contains(light.key),
                  light.roomName != wakeRoom,
                  !home.hasManualColor(light.id),
                  // Compared within the light's range, so a target it can't reach isn't resent forever.
                  abs((1_000_000 / kelvin).clamped(to: light.colorTemperatureRange) - mireds) > 10 else { continue }
            home.adaptWhite(kelvin: kelvin, for: light.id)
        }
    }
}
