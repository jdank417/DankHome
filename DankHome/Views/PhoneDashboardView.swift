//
//  PhoneDashboardView.swift
//  DankHome
//
//  The iPhone layout. The iPad dashboard fits everything on one screen, which can't
//  work on a phone, so this is one scrolling column of full-width cards sized for a
//  thumb: rooms and scenes scroll sideways, lights are a two-column grid you can
//  swipe sideways to dim, and everything else stacks below.
//

import MusicKit
import SwiftUI

struct PhoneDashboardView: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @Environment(SceneRecorder.self) private var recorder
    @Environment(WeatherStore.self) private var weather
    @ObservedObject private var queue = SystemMusicPlayer.shared.queue
    @State private var showSettings = false
    @State private var showAssistant = false
    @State private var showEnergy = false
    @State private var showAutomations = false
    @State private var talk = PushToTalk()

    private var artworkColor: Color {
        queue.currentEntry?.artwork?.backgroundColor.map(Color.init(cgColor:)) ?? .indigo
    }

    private var lightGlow: Color {
        home.visibleLights.first(where: \.isOn)?.tint ?? Color(white: 0.15)
    }

    var body: some View {
        let prefs = settings.prefs
        GeometryReader { proxy in
            let width = proxy.size.width - Metrics.margin * 2
            ZStack {
                AmbientBackground(theme: prefs.theme, accent: artworkColor, glow: lightGlow)
                if prefs.weatherEffects, let current = weather.current {
                    WeatherEffectsView(effect: WeatherEffect(code: current.code))
                        .ignoresSafeArea()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if recorder.isRecording { RecordingBanner() }
                        header
                        if home.roomNames.count > 1 { PhoneRoomChips() }
                        if prefs.showScenes { PhoneScenesRow() }
                        if prefs.showMusic { NowPlayingCard(twoRows: true) }
                        PhoneLightsSection()
                        if prefs.showDevices, !home.visibleDevices.isEmpty {
                            VStack(alignment: .leading, spacing: Metrics.gap) {
                                SectionHeader(title: "Devices", symbol: "square.grid.2x2.fill")
                                DevicesRow(width: width, maxRows: .max)
                            }
                        }
                        if prefs.showClimate, let thermostat = home.visibleThermostats.first {
                            ThermostatCard(thermostat: thermostat, dialSize: 140)
                        }
                        if prefs.showWeather { PhoneWeatherCard() }
                        ComingUpCard { showAutomations = true }
                    }
                    .padding(.horizontal, Metrics.margin)
                    .padding(.bottom, 32)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
            .overlay(alignment: .top) {
                PushToTalkBubble(talk: talk)
                    .padding(.horizontal, Metrics.margin)
                    .padding(.top, 8)
            }
            .overlay {
                // Red frame while a scene button is being recorded.
                if recorder.isRecording {
                    RoundedRectangle(cornerRadius: 44)
                        .stroke(.red, lineWidth: 4)
                        .shadow(color: .red.opacity(0.8), radius: 12)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: recorder.isRecording)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showAssistant) {
            AssistantView()
        }
        .sheet(isPresented: $showEnergy) {
            EnergyView()
        }
        .sheet(isPresented: $showAutomations) {
            NavigationStack {
                AutomationSettings()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showAutomations = false }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(item: Bindable(recorder).review) { review in
            RecordingReviewView(review: review)
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording { showSettings = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: Metrics.chipGap) {
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.greeting(at: context.date))
                            .font(.title2.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 6) {
                            Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            if home.isDemo {
                                Text("Demo")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.15), in: .capsule)
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                if !recorder.isRecording {
                    AssistantButton(talk: talk) { showAssistant = true }
                    Button {
                        Feedback.tap()
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.body.weight(.semibold))
                            .frame(width: Metrics.headerHeight, height: Metrics.headerHeight)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Settings")
                }
            }

            // The status line scrolls sideways instead of being cut off; tap it for What's On.
            TimelineView(.everyMinute) { context in
                ScrollView(.horizontal) {
                    StatusLine(now: context.date)
                        .contentShape(.rect)
                        .onTapGesture {
                            Feedback.tap()
                            showEnergy = true
                        }
                }
                .scrollIndicators(.hidden)
            }

            if let problem = home.authorizationProblem, !home.isDemo {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good Morning"
        case 12..<17: "Good Afternoon"
        case 17..<22: "Good Evening"
        default: "Good Night"
        }
    }
}

// MARK: - Sideways rows

/// Capsule buttons in a row that scrolls sideways, edge to edge.
struct ScrollingChips<Item: Identifiable>: View {
    var items: [Item]
    var title: (Item) -> String
    var symbol: (Item) -> String? = { _ in nil }
    var isSelected: (Item) -> Bool = { _ in false }
    var action: (Item) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: Metrics.chipGap) {
                HStack(spacing: Metrics.chipGap) {
                    ForEach(items) { item in
                        let selected = isSelected(item)
                        Button {
                            Feedback.tap()
                            withAnimation(.snappy) { action(item) }
                        } label: {
                            Group {
                                if let symbol = symbol(item) {
                                    Label(title(item), systemImage: symbol)
                                } else {
                                    Text(title(item))
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .black : .white)
                            .lineLimit(1)
                            .padding(.horizontal, 16)
                            .frame(height: Metrics.headerHeight + 4)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(.white).interactive() : .regular.interactive(), in: .capsule)
                    }
                }
                .padding(.horizontal, Metrics.margin)
            }
        }
        .scrollIndicators(.hidden)
        // Let the row run to the screen edges while lining up with the cards.
        .padding(.horizontal, -Metrics.margin)
    }
}

private struct RoomChip: Identifiable {
    var id: String
    var title: String
}

struct PhoneRoomChips: View {
    @Environment(HomeStore.self) private var home
    private static let allID = "__all__"

    var body: some View {
        ScrollingChips(
            items: [RoomChip(id: Self.allID, title: "All Rooms")] + home.roomNames.map { RoomChip(id: $0, title: $0) },
            title: { $0.title },
            isSelected: { $0.id == (home.selectedRoom ?? Self.allID) }
        ) { chip in
            home.selectedRoom = chip.id == Self.allID ? nil : chip.id
        }
    }
}

struct PhoneScenesRow: View {
    @Environment(HomeStore.self) private var home
    @Environment(MusicStore.self) private var music
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let buttons = settings.sceneButtons(home: home)
        if !buttons.isEmpty {
            ScrollingChips(items: buttons, title: { $0.name.isEmpty ? "New Button" : $0.name }, symbol: { $0.symbol }) { button in
                Feedback.press()
                SceneRunner(home: home, music: music, settings: settings).run(button)
            }
        }
    }
}

// MARK: - Lights

/// Two columns of light tiles. Unlike the iPad, the page scrolls, so the grid just grows.
struct PhoneLightsSection: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    @State private var detailLight: Light?

    private var orderedLights: [Light] {
        let saved = settings.prefs.lightOrder.isEmpty ? settings.prefs.pinnedLights : settings.prefs.lightOrder
        return GridReorder.sorted(home.visibleLights, by: saved, key: \.key)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.gap) {
            LightsHeader()
            if home.visibleLights.isEmpty {
                Label("No lights in this room. Add them in the Home app.", systemImage: "lightbulb.slash")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Metrics.gap), count: 2),
                          spacing: Metrics.gap) {
                    ForEach(orderedLights) { light in
                        PhoneLightTile(light: light, showsRoom: home.selectedRoom == nil) {
                            detailLight = light
                        }
                    }
                }
            }
        }
        .sheet(item: $detailLight) { light in
            LightDetailView(lightID: light.id)
        }
    }
}

/// A light as a sideways slider: the lit part fills from the left to the brightness,
/// and swiping left or right dims it (up and down scrolls the page). Tap to toggle,
/// hold for color.
struct PhoneLightTile: View {
    @Environment(HomeStore.self) private var home
    var light: Light
    var showsRoom: Bool
    var onLongPress: () -> Void

    @State private var dragStart: Double?
    @State private var lastTick: Int?
    @State private var width: CGFloat = 160

    private static let height: CGFloat = 76
    private var level: Double { light.isOn ? (light.brightness ?? 100) / 100 : 0 }
    /// A sliver stays lit at very low brightness.
    private var fill: Double { light.isOn ? max(level, 0.08) : 0 }

    var body: some View {
        ZStack {
            content(.white)
            // Dark text over the lit part, so it reads right at the edge of the fill.
            content(.black)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: width * fill)
                }
        }
        .background(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.92))
                .overlay(light.tint.opacity(0.22))
                .frame(width: width * fill)
        }
        .frame(height: Self.height)
        .clipShape(.rect(cornerRadius: Metrics.radius))
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Metrics.radius))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .opacity(light.isReachable ? 1 : 0.55)
        .contentShape(.rect(cornerRadius: Metrics.radius))
        .onTapGesture {
            Feedback.tap()
            withAnimation(.snappy) { home.toggle(light) }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            Feedback.press()
            onLongPress()
        }
        .simultaneousGesture(dimGesture)
        .animation(dragStart == nil ? .snappy : nil, value: light)
        .accessibilityElement(children: .combine)
        .accessibilityValue(statusText)
        .accessibilityAdjustableAction { direction in
            guard light.brightness != nil else { return }
            let step: Double = direction == .increment ? 10 : -10
            home.setBrightness(((light.isOn ? light.brightness ?? 0 : 0) + step).clamped(to: 0...100), for: light.id, commit: true)
        }
    }

    private func content(_ color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: light.isOn ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(light.isOn ? light.tint : .white.opacity(0.5))
                .shadow(color: light.isOn ? light.tint.opacity(0.8) : .clear, radius: 8)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(light.isOn ? 0.9 : 0.1)))
            VStack(alignment: .leading, spacing: 1) {
                Text(light.name)
                    .font(.subheadline.weight(.semibold))
                Text(showsRoom ? "\(light.roomName) · \(statusText)" : statusText)
                    .font(.caption.weight(.medium))
                    .opacity(0.75)
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if !light.isReachable {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusText: String {
        guard light.isReachable else { return "No Response" }
        guard light.isOn else { return "Off" }
        if let brightness = light.brightness { return "\(Int(brightness))%" }
        return "On"
    }

    /// Right brightens, left dims; the tile's width spans 0–100%.
    private var dimGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard light.brightness != nil, light.isReachable,
                      dragStart != nil || abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                let start = dragStart ?? (light.isOn ? light.brightness ?? 100 : 0)
                dragStart = start
                let brightness = (start + Double(value.translation.width / max(width, 120)) * 100).clamped(to: 0...100)
                let tick = Int(brightness / 10)
                if tick != lastTick {
                    if lastTick != nil { Feedback.tick() }
                    lastTick = tick
                }
                home.setBrightness(brightness, for: light.id, commit: false)
            }
            .onEnded { _ in
                guard dragStart != nil else { return }
                dragStart = nil
                lastTick = nil
                let current = home.lights.first { $0.id == light.id }
                home.setBrightness(current?.isOn == true ? current?.brightness ?? 0 : 0, for: light.id, commit: true)
            }
    }
}

// MARK: - Weather

/// Now, today's range, and the next twelve hours in a row that scrolls sideways.
struct PhoneWeatherCard: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let prefs = settings.prefs
        if let current = weather.current {
            VStack(alignment: .leading, spacing: Metrics.inner) {
                HStack(alignment: .center, spacing: Metrics.inner) {
                    Image(systemName: WeatherCode.symbol(current.code, isDay: current.isDay))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 34))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(prefs.formatTemperature(celsius: current.temperature))
                            .font(.system(size: 34, weight: .light))
                        Text(WeatherCode.description(current.code))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(weather.placeName.isEmpty ? "Weather" : weather.placeName)
                            .font(.subheadline.weight(.semibold))
                        Text("H:\(prefs.formatTemperature(celsius: current.high)) L:\(prefs.formatTemperature(celsius: current.low))")
                        Text("Feels \(prefs.formatTemperature(celsius: current.feelsLike)) · \(Int(current.humidity))%")
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                }
                Divider().overlay(.white.opacity(0.15))
                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach(weather.hours) { hour in
                            VStack(spacing: 6) {
                                Text(hour.id, format: .dateTime.hour())
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                                    .symbolRenderingMode(.multicolor)
                                    .frame(height: 22)
                                Text(prefs.formatTemperature(celsius: hour.temperature))
                                    .font(.subheadline.weight(.semibold))
                            }
                            .fixedSize()
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .card()
        } else if let error = weather.errorMessage {
            Label(error, systemImage: "cloud.slash")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }
}

// MARK: - Coming up

/// Timers and the next few routines. Tap to manage them.
struct ComingUpCard: View {
    @Environment(AutomationStore.self) private var automation
    var onTap: () -> Void

    private struct Entry: Identifiable {
        var id: String
        var symbol: String
        var title: String
        var date: Date
    }

    private func entries(now: Date) -> [Entry] {
        let timers = automation.timers.map {
            Entry(id: $0.id.uuidString, symbol: "timer", title: $0.command.capitalizedFirst, date: $0.fireDate)
        }
        let routines = automation.routines.filter(\.isEnabled).compactMap { routine -> Entry? in
            guard let next = routine.nextDue(after: now, sun: automation.sunTimes(for:)) else { return nil }
            return Entry(id: routine.id.uuidString, symbol: "clock.arrow.2.circlepath", title: routine.command.capitalizedFirst, date: next)
        }
        return (timers + routines).sorted { $0.date < $1.date }.prefix(4).map { $0 }
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            let entries = entries(now: context.date)
            Button(action: onTap) {
                VStack(alignment: .leading, spacing: Metrics.inner) {
                    HStack {
                        SectionTitle(title: "Coming Up", symbol: "clock.fill")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if entries.isEmpty {
                        Text("No timers or routines. Try asking the assistant: “every night at 10, run Good Night.”")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                            .multilineTextAlignment(.leading)
                    } else {
                        ForEach(entries) { entry in
                            HStack(spacing: Metrics.inner) {
                                Image(systemName: entry.symbol)
                                    .foregroundStyle(.orange)
                                    .frame(width: 22)
                                Text(entry.title)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                Text(Self.when(entry.date, now: context.date))
                                    .foregroundStyle(.white.opacity(0.6))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .card()
        }
    }

    /// "in 25 min", "10:00 PM", "Tue 7:00 AM".
    private static func when(_ date: Date, now: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds < 3600 { return "in \(EnergyFormat.duration(seconds + 59))" }
        if Calendar.current.isDate(date, inSameDayAs: now) { return date.formatted(date: .omitted, time: .shortened) }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
