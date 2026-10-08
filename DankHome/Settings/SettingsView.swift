//
//  SettingsView.swift
//  DankHome
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            List {
                Section {
                    NavigationLink { ClockSettings() } label: {
                        row("Clock", "clock.fill", .blue, detail: settings.prefs.clock.font.title)
                    }
                    NavigationLink { NightClockSettings() } label: {
                        row("Night Clock", "moon.stars.fill", .indigo,
                            detail: settings.prefs.nightEnabled ? "After \(settings.prefs.nightIdleMinutes) min" : "Off")
                    }
                    NavigationLink { AppearanceSettings() } label: {
                        row("Appearance", "paintpalette.fill", .pink, detail: settings.prefs.theme.title)
                    }
                    NavigationLink { DashboardSettings() } label: {
                        row("Dashboard", "square.grid.2x2.fill", .orange, detail: nil)
                    }
                    NavigationLink { WeatherSettings() } label: {
                        row("Weather", "cloud.sun.fill", .cyan,
                            detail: settings.prefs.useCurrentLocation ? "Current Location" : settings.prefs.cityName)
                    }
                }

                Section {
                    Label("Press and hold a light to change its color, warmth and brightness.", systemImage: "hand.tap.fill")
                    Label("Thermostats, lights and scenes come from the Home app — add them there.", systemImage: "house.fill")
                } header: {
                    Text("Tips")
                }

                Section {
                    Button("Reset All Settings", role: .destructive) { confirmReset = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Reset all settings to their defaults?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset", role: .destructive) { settings.reset() }
            }
        }
    }

    private func row(_ title: String, _ symbol: String, _ color: Color, detail: String?) -> some View {
        HStack {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color.gradient, in: .rect(cornerRadius: 8))
            }
            Spacer()
            if let detail {
                Text(detail).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Clock

struct ClockSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            ClockStyleEditor(style: $settings.prefs.clock, prefs: settings.prefs, showsDate: settings.prefs.showDate)
            Section {
                Toggle("24-Hour Time", isOn: $settings.prefs.use24Hour)
                Toggle("Show Date", isOn: $settings.prefs.showDate)
            }
        }
        .navigationTitle("Clock")
    }
}

/// Lock Screen–style editor: live preview, font grid, weight slider and color.
struct ClockStyleEditor: View {
    @Binding var style: ClockStyle
    var prefs: Preferences
    var showsDate: Bool
    var dimming: Double = 1

    var body: some View {
        Section {
            TimelineView(.everyMinute) { context in
                VStack(spacing: 4) {
                    if showsDate {
                        Text(context.date, format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.title3.weight(.semibold))
                    }
                    Text(prefs.formatTime(context.date))
                        .font(style.font(size: 110))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .foregroundStyle(style.color.color)
                .opacity(dimming)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(
                    LinearGradient(colors: [Color(white: 0.05), Color(red: 0.1, green: 0.08, blue: 0.2)],
                                   startPoint: .top, endPoint: .bottom),
                    in: .rect(cornerRadius: 20)
                )
                .animation(.snappy, value: style)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }

        Section("Font") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 12)], spacing: 12) {
                ForEach(ClockFont.allCases) { font in
                    let selected = style.font == font
                    Button {
                        style.font = font
                    } label: {
                        VStack(spacing: 6) {
                            Text("12")
                                .font(ClockStyle(font: font, weight: style.weight).font(size: 44))
                            Text(font.title).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(.white.opacity(selected ? 0.18 : 0.06), in: .rect(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 6)

            HStack {
                Text("Aa").font(.system(size: 16, weight: .ultraLight))
                Slider(value: $style.weight, in: 0...Double(ClockStyle.weights.count - 1), step: 1)
                Text("Aa").font(.system(size: 22, weight: .black))
            }
        }

        Section("Color") {
            ColorSwatchRow(color: $style.color)
        }
    }
}

struct ColorSwatchRow: View {
    @Binding var color: RGBAColor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(RGBAColor.swatches, id: \.self) { swatch in
                    Button {
                        color = swatch
                    } label: {
                        Circle()
                            .fill(swatch.color)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(.primary, lineWidth: isSelected(swatch) ? 3 : 0).padding(-4))
                    }
                    .buttonStyle(.plain)
                }
                ColorPicker("Custom", selection: $color.color, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.3)
                    .padding(.leading, 6)
            }
            .padding(8)
        }
    }

    private func isSelected(_ swatch: RGBAColor) -> Bool {
        abs(swatch.red - color.red) + abs(swatch.green - color.green) + abs(swatch.blue - color.blue) < 0.03
    }
}

// MARK: - Night clock

struct NightClockSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(IdleMonitor.self) private var idle

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Toggle("Night Clock", isOn: $settings.prefs.nightEnabled)
                Picker("Start After", selection: $settings.prefs.nightIdleMinutes) {
                    ForEach([1, 2, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) min").tag($0) }
                }
                Button("Preview Now") {
                    idle.sleep(settings.prefs)
                }
            } footer: {
                Text("When nobody has touched the screen for a while, DankHome switches to a dim clock. Tap anywhere to wake it. The clock drifts slightly each minute to protect the screen.")
            }

            ClockStyleEditor(style: $settings.prefs.nightClock, prefs: settings.prefs,
                             showsDate: settings.prefs.nightShowDate, dimming: settings.prefs.nightBrightness)

            Section("Brightness") {
                HStack {
                    Image(systemName: "sun.min")
                    Slider(value: $settings.prefs.nightBrightness, in: 0.1...1)
                    Image(systemName: "sun.max.fill")
                }
                Toggle("Dim Screen Backlight", isOn: $settings.prefs.nightDimsScreen)
                if settings.prefs.nightDimsScreen {
                    HStack {
                        Image(systemName: "iphone.gen3.radiowaves.left.and.right").hidden()
                        Slider(value: $settings.prefs.nightScreenLevel, in: 0...0.6)
                        Text("\(Int(settings.prefs.nightScreenLevel * 100))%").monospacedDigit()
                    }
                }
            }

            Section("Show") {
                Toggle("Date", isOn: $settings.prefs.nightShowDate)
                Toggle("Weather", isOn: $settings.prefs.nightShowWeather)
                Toggle("Now Playing", isOn: $settings.prefs.nightShowMusic)
            }
        }
        .navigationTitle("Night Clock")
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
                    ForEach(BackgroundTheme.allCases) { theme in
                        let selected = settings.prefs.theme == theme
                        Button {
                            settings.prefs.theme = theme
                        } label: {
                            VStack(spacing: 8) {
                                ThemeSwatch(theme: theme)
                                    .frame(height: 80)
                                    .overlay(RoundedRectangle(cornerRadius: 14)
                                        .stroke(selected ? Color.accentColor : .white.opacity(0.15), lineWidth: selected ? 3 : 1))
                                Text(theme.title).font(.caption.weight(.medium))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 6)
            } header: {
                Text("Background")
            } footer: {
                Text("Ambient follows the album art and the color of your lights.")
            }

            Section("Accent Color") {
                ColorSwatchRow(color: $settings.prefs.accent)
            }

            Section("App Font") {
                Picker("App Font", selection: $settings.prefs.appFont) {
                    ForEach(AppFont.allCases) { font in
                        Text(font.title).fontDesign(font.design).tag(font)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Appearance")
    }
}

private struct ThemeSwatch: View {
    var theme: BackgroundTheme

    var body: some View {
        let (base, a, b) = theme == .ambient
            ? (Color(red: 0.04, green: 0.04, blue: 0.08), Color.pink, Color.orange)
            : theme.colors
        RoundedRectangle(cornerRadius: 14)
            .fill(base)
            .overlay {
                ZStack {
                    Circle().fill(a.opacity(0.7)).blur(radius: 18).offset(x: 30, y: -20)
                    Circle().fill(b.opacity(0.5)).blur(radius: 18).offset(x: -30, y: 20)
                }
            }
            .clipShape(.rect(cornerRadius: 14))
    }
}

// MARK: - Dashboard

struct DashboardSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Light Tiles") {
                Picker("Size", selection: $settings.prefs.tileSize) {
                    ForEach(TileSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section("Layout") {
                Picker("Music Panel", selection: $settings.prefs.musicOnLeft) {
                    Text("Right").tag(false)
                    Text("Left").tag(true)
                }
                Toggle("Weather", isOn: $settings.prefs.showWeather)
                Toggle("Thermostat", isOn: $settings.prefs.showClimate)
                Toggle("Scenes", isOn: $settings.prefs.showScenes)
                Toggle("Playlists", isOn: $settings.prefs.showPlaylists)
            }
            Section {
                Toggle("Keep Screen On", isOn: $settings.prefs.keepAwake)
            } footer: {
                Text("Stops the iPad from auto-locking while DankHome is open. For a wall panel, also turn on Guided Access in Settings › Accessibility.")
            }
        }
        .navigationTitle("Dashboard")
    }
}

// MARK: - Weather

struct WeatherSettings: View {
    @Environment(AppSettings.self) private var settings
    @State private var query = ""
    @State private var results: [City] = []

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                Picker("Units", selection: $settings.prefs.temperatureUnit) {
                    ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
            } footer: {
                Text("Also used for the thermostat.")
            }

            Section("Location") {
                Toggle("Use Current Location", isOn: $settings.prefs.useCurrentLocation)
                if !settings.prefs.useCurrentLocation {
                    if !settings.prefs.cityName.isEmpty {
                        Label(settings.prefs.cityName, systemImage: "mappin.circle.fill")
                    }
                    TextField("Search for a city", text: $query)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    ForEach(results) { city in
                        Button {
                            settings.prefs.cityName = city.name
                            settings.prefs.cityLatitude = city.latitude
                            settings.prefs.cityLongitude = city.longitude
                            query = ""
                            results = []
                        } label: {
                            VStack(alignment: .leading) {
                                Text(city.name)
                                Text(city.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Link("Weather data by Open-Meteo.com", destination: URL(string: "https://open-meteo.com")!)
                    .font(.footnote)
            }
        }
        .navigationTitle("Weather")
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            results = await WeatherStore.searchCities(query)
        }
    }
}
