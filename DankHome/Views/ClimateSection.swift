//
//  ClimateSection.swift
//  DankHome
//

import SwiftUI

/// Big temperature in the header with today's high/low.
struct WeatherSummary: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let prefs = settings.prefs
        if let current = weather.current {
            HStack(spacing: 16) {
                Image(systemName: WeatherCode.symbol(current.code, isDay: current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 52))
                VStack(alignment: .leading, spacing: 2) {
                    Text(prefs.formatTemperature(celsius: current.temperature))
                        .font(.system(size: 52, weight: .light))
                    Text("\(WeatherCode.description(current.code)) · H:\(prefs.formatTemperature(celsius: current.high)) L:\(prefs.formatTemperature(celsius: current.low))")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                    if !weather.placeName.isEmpty {
                        Label(weather.placeName, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .foregroundStyle(.white)
        } else if let error = weather.errorMessage {
            Label(error, systemImage: "cloud.slash")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

/// Next few hours of weather.
struct ForecastCard: View {
    @Environment(WeatherStore.self) private var weather
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if let current = weather.current {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(title: "Forecast", symbol: "cloud.sun.fill")
                HStack(spacing: 0) {
                    ForEach(weather.hours) { hour in
                        VStack(spacing: 10) {
                            Text(hour.id, format: .dateTime.hour())
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white.opacity(0.7))
                            Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
                                .symbolRenderingMode(.multicolor)
                                .font(.title2)
                                .frame(height: 30)
                            Text(settings.prefs.formatTemperature(celsius: hour.temperature))
                                .font(.title3.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 20) {
                    Label("Feels \(settings.prefs.formatTemperature(celsius: current.feelsLike))", systemImage: "thermometer.medium")
                    Label("\(Int(current.humidity))%", systemImage: "humidity.fill")
                }
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

/// HomeKit thermostat: dial, +/- and mode.
struct ThermostatCard: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    var thermostat: Thermostat

    private var step: Double {
        // 1°F ≈ 0.5°C, so both units move one displayed degree per tap.
        settings.prefs.temperatureUnit == .fahrenheit ? 5.0 / 9.0 : 0.5
    }

    var body: some View {
        let prefs = settings.prefs
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SectionTitle(title: thermostat.name, symbol: "thermometer.medium")
                Spacer()
                if let humidity = thermostat.humidity {
                    Label("\(Int(humidity))%", systemImage: "humidity.fill")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            HStack(spacing: 20) {
                adjustButton("minus") { home.setTarget(thermostat.targetC - step, for: thermostat.id) }
                dial(prefs)
                adjustButton("plus") { home.setTarget(thermostat.targetC + step, for: thermostat.id) }
            }
            .frame(maxWidth: .infinity)
            .disabled(thermostat.mode == .off)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Thermostat.Mode.allCases) { mode in
                        let selected = thermostat.mode == mode
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.snappy) { home.setMode(mode, for: thermostat.id) }
                        } label: {
                            Label(mode.title, systemImage: mode.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(selected ? .black : .white)
                                .padding(.vertical, 10)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(mode == .off ? .white : thermostat.color).interactive()
                                              : .regular.interactive(), in: .capsule)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .card()
        .opacity(thermostat.isReachable ? 1 : 0.55)
    }

    private func dial(_ prefs: Preferences) -> some View {
        let progress = ((thermostat.targetC - thermostat.minC) / (thermostat.maxC - thermostat.minC)).clamped(to: 0...1)
        return ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * (thermostat.mode == .off ? 0 : progress))
                .stroke(thermostat.color.gradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: thermostat.color.opacity(0.6), radius: 10)
            VStack(spacing: 2) {
                Text(statusText)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(thermostat.color)
                Text(thermostat.mode == .off ? "Off" : prefs.formatTemperature(celsius: thermostat.targetC))
                    .font(.system(size: 56, weight: .light))
                    .contentTransition(.numericText())
                Text("Now \(prefs.formatTemperature(celsius: thermostat.currentC))")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 190, height: 190)
        .animation(.snappy, value: thermostat)
    }

    private var statusText: String {
        switch (thermostat.mode, thermostat.activity) {
        case (.off, _): "Off"
        case (_, .heating): "Heating"
        case (_, .cooling): "Cooling"
        default: "Idle"
        }
    }

    private func adjustButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Thermostats + forecast, shown together.
struct ClimateSection: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    var sideBySide: Bool

    var body: some View {
        let thermostats = settings.prefs.showClimate ? home.visibleThermostats : []
        let layout = sideBySide ? AnyLayout(HStackLayout(alignment: .top, spacing: 16)) : AnyLayout(VStackLayout(spacing: 16))
        if !thermostats.isEmpty || settings.prefs.showWeather {
            layout {
                ForEach(thermostats) { ThermostatCard(thermostat: $0) }
                if settings.prefs.showWeather { ForecastCard() }
            }
        }
    }
}
