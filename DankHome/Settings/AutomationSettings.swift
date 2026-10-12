//
//  AutomationSettings.swift
//  DankHome
//
//  Settings › Automations: timers, routines, the wake-up light and adaptive lighting.
//

import SwiftUI

struct AutomationSettings: View {
    @Environment(AutomationStore.self) private var automation
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @State private var editing: Routine?
    @State private var addingTimer = false

    var body: some View {
        @Bindable var settings = settings
        Form {
            timersSection
            routinesSection
            WakeAlarmSection(alarm: $settings.prefs.wakeAlarm)
            AdaptiveLightingSection()
        }
        .navigationTitle("Automations")
        .sheet(item: $editing) { routine in
            RoutineEditor(routine: routine, isNew: !automation.routines.contains { $0.id == routine.id })
        }
        .sheet(isPresented: $addingTimer) {
            AddTimerView()
                .presentationDetents([.medium])
        }
    }

    // MARK: Timers

    private var timersSection: some View {
        Section {
            ForEach(automation.timers) { timer in
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    HStack {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(timer.command.capitalizedFirst)
                                Text("\(timer.fireDate.formatted(date: .omitted, time: .shortened)) · in \(EnergyFormat.duration(timer.fireDate.timeIntervalSince(context.date) + 59))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "timer").foregroundStyle(.orange)
                        }
                        Spacer()
                        Button("Cancel", role: .destructive) {
                            withAnimation { automation.cancelTimer(timer.id) }
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            Button {
                addingTimer = true
            } label: {
                Label("Add Timer", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Timers")
        } footer: {
            Text("Or just ask the assistant: “turn off the lights in 30 minutes.” Timers run while DankHome is open.")
        }
    }

    // MARK: Routines

    private var routinesSection: some View {
        Section {
            ForEach(automation.routines) { routine in
                HStack {
                    // The toggle sits beside the button, not inside it, so both stay tappable.
                    Button {
                        editing = routine
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.command.capitalizedFirst)
                                .foregroundStyle(.primary)
                            Text(routine.scheduleText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if routine.hubTriggerID != nil {
                                Label("On your home hub", systemImage: "homekit")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    Toggle("Enabled", isOn: Binding(
                        get: { routine.isEnabled },
                        set: { automation.setEnabled($0, for: routine.id) }
                    ))
                    .labelsHidden()
                }
            }
            .onDelete { offsets in
                for index in offsets { automation.remove(automation.routines[index]) }
            }
            Button {
                let scene = settings.sceneButtons(home: home).first?.name ?? "Good Night"
                editing = Routine(command: "run \(scene)", time: .clock(hour: 22, minute: 0))
            } label: {
                Label("Add Routine", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Routines")
        } footer: {
            Text("Or ask the assistant: “every night at 10, run Good Night.” Routines that run a Home app scene are saved to your home hub, so they happen even when DankHome is closed.")
        }
    }
}

/// Automations on its own, with a Done button, for opening straight from the dashboard.
struct AutomationsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AutomationSettings()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Routine editor

struct RoutineEditor: View {
    @Environment(AutomationStore.self) private var automation
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home
    @Environment(\.dismiss) private var dismiss
    @State var routine: Routine
    var isNew: Bool
    @State private var result: String?

    private enum When: String, CaseIterable, Identifiable {
        case clock = "Time", sunrise = "Sunrise", sunset = "Sunset"
        var id: Self { self }
    }

    private var when: Binding<When> {
        Binding(
            get: {
                switch routine.time {
                case .clock: .clock
                case .sunrise: .sunrise
                case .sunset: .sunset
                }
            },
            set: { kind in
                let offset: Int = switch routine.time {
                case .sunrise(let minutes), .sunset(let minutes): minutes
                case .clock: 0
                }
                routine.time = switch kind {
                case .clock: .clock(hour: 22, minute: 0)
                case .sunrise: .sunrise(offsetMinutes: offset)
                case .sunset: .sunset(offsetMinutes: offset)
                }
            }
        )
    }

    private var clockTime: Binding<Date> {
        Binding(
            get: {
                guard case .clock(let hour, let minute) = routine.time else { return .now }
                return Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                routine.time = .clock(hour: parts.hour ?? 22, minute: parts.minute ?? 0)
            }
        )
    }

    private var offset: Binding<Int> {
        Binding(
            get: {
                switch routine.time {
                case .sunrise(let minutes), .sunset(let minutes): minutes
                case .clock: 0
                }
            },
            set: { minutes in
                switch routine.time {
                case .sunrise: routine.time = .sunrise(offsetMinutes: minutes)
                case .sunset: routine.time = .sunset(offsetMinutes: minutes)
                case .clock: break
                }
            }
        )
    }

    /// Ready-made commands from the home's own scenes and devices.
    private var suggestions: [String] {
        var list = settings.sceneButtons(home: home).map { "run \($0.name)" }
        list.append("turn off all the lights")
        list += home.devices.filter { $0.kind == .lock }.map { "lock the \($0.name)" }
        list += home.devices.filter { $0.kind == .shade }.flatMap { ["open the \($0.name)", "close the \($0.name)"] }
        list += home.devices.filter { $0.kind == .garage }.map { "close the \($0.name)" }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("run Good Night", text: $routine.command)
                        .textInputAutocapitalization(.never)
                    Menu {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button(suggestion.capitalizedFirst) { routine.command = suggestion }
                        }
                    } label: {
                        Label("Choose", systemImage: "list.bullet")
                    }
                } header: {
                    Text("Do")
                } footer: {
                    Text("Anything you'd say to the assistant, like “close the shades” or “set the thermostat to 66”.")
                }

                Section("When") {
                    Picker("When", selection: when) {
                        ForEach(When.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if case .clock = routine.time {
                        DatePicker("Time", selection: clockTime, displayedComponents: .hourAndMinute)
                    } else {
                        Stepper(value: offset, in: -120...120, step: 15) {
                            Text(routine.time.text.capitalizedFirst)
                        }
                    }
                    WeekdayPicker(days: $routine.days)
                }

                Section {
                    Button {
                        Task { result = await automation.runNow(routine) }
                    } label: {
                        Label("Try It Now", systemImage: "play.fill")
                    }
                    if let result {
                        Text(result).font(.footnote).foregroundStyle(.secondary)
                    }
                    if !isNew {
                        Button("Delete Routine", role: .destructive) {
                            automation.remove(routine)
                            dismiss()
                        }
                    }
                } footer: {
                    Text(automation.hubSceneName(for: routine.command) != nil && !home.isDemo
                         ? "This runs a Home app scene, so it's saved to your home hub and happens even when DankHome is closed."
                         : "Runs while DankHome is open.")
                }
            }
            .navigationTitle(isNew ? "New Routine" : "Routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        routine.command = routine.command.trimmingCharacters(in: .whitespacesAndNewlines)
                        automation.save(routine)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(routine.command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Seven day toggles. Empty means every day; at least one day stays on.
struct WeekdayPicker: View {
    @Binding var days: Set<Int>

    private var order: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(order, id: \.self) { day in
                    let on = days.isEmpty || days.contains(day)
                    Button {
                        toggle(day)
                    } label: {
                        Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(on ? .black : .primary)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(on ? Color.accentColor : Color.white.opacity(0.08), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Calendar.current.weekdaySymbols[day - 1])
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text(Routine.daysText(days))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ day: Int) {
        var updated = days.isEmpty ? Set(1...7) : days
        if updated.contains(day) { updated.remove(day) } else { updated.insert(day) }
        guard !updated.isEmpty else { return }
        days = updated.count == 7 ? [] : updated
    }
}

// MARK: - Timers

struct AddTimerView: View {
    @Environment(AutomationStore.self) private var automation
    @Environment(\.dismiss) private var dismiss
    @State private var command = "turn off all the lights"
    @State private var minutes = 30

    var body: some View {
        NavigationStack {
            Form {
                Section("Do") {
                    TextField("turn off all the lights", text: $command)
                        .textInputAutocapitalization(.never)
                }
                Section("In") {
                    Picker("Minutes", selection: $minutes) {
                        ForEach([5, 10, 15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { value in
                            Text(EnergyFormat.duration(TimeInterval(value * 60))).tag(value)
                        }
                    }
                }
            }
            .navigationTitle("New Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        automation.addTimer(command, after: TimeInterval(minutes * 60))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Wake-up light

struct WakeAlarmSection: View {
    @Environment(HomeStore.self) private var home
    @Binding var alarm: WakeAlarm

    private var rooms: [String] {
        Array(Set(home.lights.filter { $0.brightness != nil }.map(\.roomName))).sorted()
    }

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: alarm.hour, minute: alarm.minute, second: 0, of: .now) ?? .now },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                alarm.hour = parts.hour ?? 7
                alarm.minute = parts.minute ?? 0
            }
        )
    }

    var body: some View {
        Section {
            Toggle("Wake-Up Light", isOn: $alarm.isEnabled)
            if alarm.isEnabled {
                DatePicker("Wake Up At", selection: time, displayedComponents: .hourAndMinute)
                Picker("Room", selection: $alarm.room) {
                    Text("Choose…").tag("")
                    ForEach(rooms, id: \.self) { Text($0).tag($0) }
                }
                Picker("Fade In Over", selection: $alarm.fadeMinutes) {
                    ForEach([10, 15, 20, 30, 45, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                WeekdayPicker(days: $alarm.days)
            }
        } header: {
            Text("Wake-Up Light")
        } footer: {
            Text("Slowly brightens the room's lights from a candle-warm glow to soft daylight, reaching full brightness at your wake-up time. Turn the lights off to stop it for the day. Works while DankHome is open.")
        }
        .onChange(of: alarm.isEnabled) { _, enabled in
            if enabled, alarm.room.isEmpty {
                alarm.room = rooms.first { $0.localizedCaseInsensitiveContains("bed") } ?? rooms.first ?? ""
            }
        }
    }
}

// MARK: - Adaptive lighting

struct AdaptiveLightingSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AutomationStore.self) private var automation

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle("Adaptive Lighting", isOn: $settings.prefs.adaptiveLighting)
            if settings.prefs.adaptiveLighting {
                if let kelvin = automation.adaptiveKelvin() {
                    LabeledContent("Right Now") {
                        HStack(spacing: 8) {
                            Circle().fill(Light.white(kelvin: kelvin)).frame(width: 16, height: 16)
                            Text(verbatim: "\(Int(kelvin.rounded(to: 50)))K").monospacedDigit()
                        }
                    }
                }
                kelvinSlider("Daytime", value: $settings.prefs.adaptiveDayKelvin, range: 3500...6500)
                kelvinSlider("Night", value: $settings.prefs.adaptiveNightKelvin, range: 2000...3000)
                NavigationLink {
                    AdaptiveLightsPicker()
                } label: {
                    LabeledContent("Lights", value: settings.prefs.adaptiveLights.isEmpty ? "All" : "\(settings.prefs.adaptiveLights.count)")
                }
            }
        } header: {
            Text("Adaptive Lighting")
        } footer: {
            Text("White lights that are on follow the sun: crisp daylight during the day, winding down to a warm glow after sunset. A light you set to a color or white yourself is left alone until it's turned off. Works while DankHome is open.")
        }
    }

    private func kelvinSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(verbatim: "\(Int(value.wrappedValue))K").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: 100)
                .tint(Light.white(kelvin: value.wrappedValue))
        }
    }
}

struct AdaptiveLightsPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HomeStore.self) private var home

    private var lights: [Light] { home.lights.filter { $0.colorTemperature != nil } }

    var body: some View {
        Form {
            Section {
                ForEach(lights) { light in
                    Toggle(isOn: Binding(
                        get: { settings.prefs.adaptiveLights.isEmpty || settings.prefs.adaptiveLights.contains(light.key) },
                        set: { on in
                            var keys = settings.prefs.adaptiveLights.isEmpty ? lights.map(\.key) : settings.prefs.adaptiveLights
                            if on { keys.append(light.key) } else { keys.removeAll { $0 == light.key } }
                            // All of them (or none left) goes back to "every light".
                            let all = Set(lights.map(\.key))
                            settings.prefs.adaptiveLights = Set(keys) == all || keys.isEmpty ? [] : keys
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(light.name)
                            Text(light.roomName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(lights.isEmpty ? "None of your lights can change their white temperature." : "Only lights that can change their white temperature are listed.")
            }
        }
        .navigationTitle("Adaptive Lights")
    }
}

extension String {
    /// "turn off the lights" → "Turn off the lights".
    var capitalizedFirst: String {
        self.prefix(1).uppercased() + self.dropFirst()
    }
}

private extension Double {
    func rounded(to step: Double) -> Double {
        (self / step).rounded() * step
    }
}
