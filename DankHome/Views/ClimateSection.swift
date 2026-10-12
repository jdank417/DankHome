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
            HStack(spacing: 10) {
                Image(systemName: WeatherCode.symbol(current.code, isDay: current.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 0) {
                    Text(prefs.formatTemperature(celsius: current.temperature))
                        .font(.system(size: 28, weight: .light))
                    Text("H:\(prefs.formatTemperature(celsius: current.high)) L:\(prefs.formatTemperature(celsius: current.low))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
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
    var hourCount = 6
    /// In a tall column, list the hours top to bottom to use the space evenly.
    var vertical = false

    var body: some View {
        if let current = weather.current {
            // The fullest version that fits the space wins; nothing ever scrolls.
            ViewThatFits(in: .vertical) {
                if vertical {
                    ForEach([10, 8, 6, 4], id: \.self) { count in
                        full(current) { hourList(count) }
                    }
                }
                full(current) { hourRow(hourCount) }
                VStack(alignment: .leading, spacing: Metrics.inner) {
                    titleRow(current)
                    hourRow(hourCount)
                }
                titleRow(current)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()
        }
    }

    private func full(_ current: CurrentWeather, @ViewBuilder hours: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Metrics.inner) {
            titleRow(current)
            hours()
                .frame(maxHeight: .infinity)
            HStack(spacing: Metrics.gap) {
                Label("Feels \(settings.prefs.formatTemperature(celsius: current.feelsLike))", systemImage: "thermometer.medium")
                Label("\(Int(current.humidity))%", systemImage: "humidity.fill")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func titleRow(_ current: CurrentWeather) -> some View {
        HStack {
            SectionTitle(title: weather.placeName.isEmpty ? "Forecast" : weather.placeName, symbol: "cloud.sun.fill")
            Spacer(minLength: 0)
            Text(WeatherCode.description(current.code))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private func hourRow(_ count: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(weather.hours.prefix(count)) { hour in
                VStack(spacing: 6) {
                    Text(hour.id, format: .dateTime.hour())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                        .fixedSize()
                    icon(hour)
                    Text(settings.prefs.formatTemperature(celsius: hour.temperature))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func hourList(_ count: Int) -> some View {
        VStack(spacing: 0) {
            ForEach(weather.hours.prefix(count)) { hour in
                HStack {
                    Text(hour.id, format: .dateTime.hour())
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 56, alignment: .leading)
                    icon(hour)
                    Spacer(minLength: 0)
                    Text(settings.prefs.formatTemperature(celsius: hour.temperature))
                        .font(.subheadline.weight(.semibold))
                }
                .frame(minHeight: 28)
                .frame(maxHeight: 36)
            }
        }
    }

    private func icon(_ hour: HourForecast) -> some View {
        Image(systemName: WeatherCode.symbol(hour.code, isDay: hour.isDay))
            .symbolRenderingMode(.multicolor)
            .font(.body)
            .frame(width: 28, height: 20)
    }
}

/// HomeKit thermostat: dial, +/- and mode.
struct ThermostatCard: View {
    @Environment(HomeStore.self) private var home
    @Environment(AppSettings.self) private var settings
    var thermostat: Thermostat
    var dialSize: CGFloat = 170

    var body: some View {
        let prefs = settings.prefs
        VStack(alignment: .leading, spacing: Metrics.inner) {
            HStack {
                SectionTitle(title: thermostat.name, symbol: "thermometer.medium")
                Spacer()
                if let humidity = thermostat.humidity {
                    Label("\(Int(humidity))%", systemImage: "humidity.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }

            Spacer(minLength: 0)
            HStack(spacing: Metrics.chipGap) {
                adjustButton("minus") { home.nudgeTarget(by: -1, unit: settings.prefs.temperatureUnit, for: thermostat.id) }
                dial(prefs)
                adjustButton("plus") { home.nudgeTarget(by: 1, unit: settings.prefs.temperatureUnit, for: thermostat.id) }
            }
            .frame(maxWidth: .infinity)
            .disabled(thermostat.mode == .off)

            Spacer(minLength: 0)
            GlassEffectContainer(spacing: Metrics.chipGap) {
                HStack(spacing: Metrics.chipGap) {
                    ForEach(Thermostat.Mode.allCases) { mode in
                        let selected = thermostat.mode == mode
                        Button {
                            Feedback.tap()
                            withAnimation(.snappy) { home.setMode(mode, for: thermostat.id) }
                        } label: {
                            Label(mode.title, systemImage: mode.symbol)
                                .labelStyle(.iconOnly)
                                .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selected ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: Metrics.headerHeight)
                            .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(selected ? .regular.tint(mode == .off ? .white : thermostat.color).interactive()
                                              : .regular.interactive(), in: .capsule)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .frame(maxHeight: .infinity)
        .card()
        .opacity(thermostat.isReachable ? 1 : 0.55)
    }

    private func dial(_ prefs: Preferences) -> some View {
        let progress = ((thermostat.targetC - thermostat.minC) / (thermostat.maxC - thermostat.minC)).clamped(to: 0...1)
        return ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: dialSize * 0.07, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * (thermostat.mode == .off ? 0 : progress))
                .stroke(thermostat.color.gradient, style: StrokeStyle(lineWidth: dialSize * 0.07, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: thermostat.color.opacity(0.6), radius: 10)
            VStack(spacing: 2) {
                Text(statusText)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(thermostat.color)
                Text(thermostat.mode == .off ? "Off" : prefs.formatTemperature(celsius: thermostat.targetC))
                    .font(.system(size: dialSize * 0.3, weight: .light))
                    .contentTransition(.numericText())
                Text("Now \(prefs.formatTemperature(celsius: thermostat.currentC))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: dialSize, height: dialSize)
        .animation(.snappy, value: thermostat)
    }

    private var statusText: String {
        if thermostat.isSending, thermostat.mode != .off { return "Setting…" }
        return switch (thermostat.mode, thermostat.activity) {
        case (.off, _): "Off"
        case (_, .heating): "Heating"
        case (_, .cooling): "Cooling"
        default: "Idle"
        }
    }

    private func adjustButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Feedback.tap()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: Metrics.headerHeight + 4, height: Metrics.headerHeight + 4)
                // The whole circle is the target, not just the thin "−" stroke.
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}
