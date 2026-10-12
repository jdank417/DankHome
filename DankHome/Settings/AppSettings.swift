//
//  AppSettings.swift
//  DankHome
//

import SwiftUI

/// Every customizable option, saved to UserDefaults as one JSON blob.
@Observable
final class AppSettings {
    var prefs: Preferences {
        didSet { save() }
    }

    private static let key = "preferences.v1"

    init() {
        prefs = Self.load() ?? Preferences()
    }

    /// Lays the saved values over the defaults, so settings added in a newer version
    /// start at their default instead of wiping everything else.
    private static func load() -> Preferences? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(Preferences()),
              var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any] else { return nil }
        for (field, value) in saved {
            merged[field] = value
        }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged) else { return nil }
        return try? JSONDecoder().decode(Preferences.self, from: mergedData)
    }

    func reset() { prefs = Preferences() }

    private func save() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

struct Preferences: Codable, Equatable {
    // Appearance
    var theme: BackgroundTheme = .ambient
    var appFont: AppFont = .classic
    var accent: RGBAColor = .init(.cyan)
    var weatherEffects = true
    var tintMusicCard = true

    // Clock
    var clock = ClockStyle()
    var use24Hour = false
    var showDate = true

    // Dashboard
    var sidePanelOnLeft = true
    var showWeather = true
    var showClimate = true
    var showScenes = true
    var showMusic = true
    var showDevices = true
    var keepAwake = true
    var demoMode = false
    var clickSounds = false
    var confirmAllOff = true
    /// Warn when a plug, switch or fan has been on this many hours (0 = never).
    var leftOnWarningHours = 4
    /// Lights shown first, as "Room|Name". Replaced by `lightOrder`; read once to migrate.
    var pinnedLights: [String] = []
    /// The order of light and device tiles on the dashboard, as "Room|Name".
    var lightOrder: [String] = []
    var deviceOrder: [String] = []
    /// nil mirrors the Home app's scenes.
    var sceneButtons: [SceneButton]?

    // Assistant
    var assistantSpeaks = true

    // Night clock
    var nightEnabled = true
    var nightIdleMinutes = 5
    var nightClock = ClockStyle(font: .classic, weight: 1, color: .init(Color(red: 1, green: 0.55, blue: 0.35)))
    var nightBrightness = 0.6
    var nightShowDate = true
    var nightShowWeather = true
    var nightShowMusic = true
    var nightDimsScreen = true
    var nightScreenLevel = 0.15
    /// Deep red between midnight and 6 AM, easy on night vision.
    var nightRedAfterMidnight = true

    // Weather
    var temperatureUnit: TemperatureUnit = Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    var useCurrentLocation = true
    var cityName = ""
    var cityLatitude = 0.0
    var cityLongitude = 0.0

    /// Changes whenever weather needs re-fetching.
    var weatherKey: String {
        "\(temperatureUnit)-\(useCurrentLocation)-\(cityLatitude)-\(cityLongitude)"
    }

    func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = use24Hour ? "HH:mm" : "h:mm"
        return formatter.string(from: date)
    }

    func formatTemperature(celsius: Double?) -> String {
        guard let celsius else { return "--°" }
        let value = temperatureUnit == .fahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }
}

// MARK: - Clock style

enum ClockFont: String, Codable, CaseIterable, Identifiable {
    case classic, rounded, serif, mono, condensed, wide
    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .rounded: "Rounded"
        case .serif: "New York"
        case .mono: "Mono"
        case .condensed: "Condensed"
        case .wide: "Wide"
        }
    }
}

struct ClockStyle: Codable, Equatable {
    var font: ClockFont = .rounded
    /// Index into `ClockStyle.weights` (0 = ultra light … 8 = black).
    var weight: Double = 1
    var color: RGBAColor = .init(.white)

    static let weights: [Font.Weight] = [.ultraLight, .thin, .light, .regular, .medium, .semibold, .bold, .heavy, .black]

    func font(size: CGFloat) -> Font {
        let weight = Self.weights[Int(weight.rounded()).clamped(to: 0...Self.weights.count - 1)]
        switch font {
        case .classic: return .system(size: size, weight: weight)
        case .rounded: return .system(size: size, weight: weight, design: .rounded)
        // New York has no weights lighter than Regular; lighter ones fall back to SF.
        case .serif: return .system(size: size, weight: Self.weights[max(Int(self.weight.rounded()), 3)], design: .serif)
        case .mono: return .system(size: size * 0.9, weight: weight, design: .monospaced)
        case .condensed: return .system(size: size * 1.1, weight: weight).width(.compressed)
        case .wide: return .system(size: size * 0.85, weight: weight).width(.expanded)
        }
    }
}

// MARK: - Appearance

enum AppFont: String, Codable, CaseIterable, Identifiable {
    case classic, rounded, serif, mono
    var id: Self { self }

    var title: String {
        switch self {
        case .classic: "Classic"
        case .rounded: "Rounded"
        case .serif: "New York"
        case .mono: "Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .classic: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}

enum BackgroundTheme: String, Codable, CaseIterable, Identifiable {
    case ambient, midnight, aurora, sunset, ocean, forest, graphite, black
    var id: Self { self }

    var title: String {
        switch self {
        case .ambient: "Ambient"
        case .midnight: "Midnight"
        case .aurora: "Aurora"
        case .sunset: "Sunset"
        case .ocean: "Ocean"
        case .forest: "Forest"
        case .graphite: "Graphite"
        case .black: "Black"
        }
    }

    /// (base, top-right glow, bottom-left glow)
    var colors: (Color, Color, Color) {
        switch self {
        case .ambient, .midnight: (Color(red: 0.04, green: 0.04, blue: 0.08), .indigo, .purple)
        case .aurora: (Color(red: 0.02, green: 0.06, blue: 0.08), .green, .purple)
        case .sunset: (Color(red: 0.08, green: 0.03, blue: 0.05), .orange, .pink)
        case .ocean: (Color(red: 0.01, green: 0.05, blue: 0.1), .cyan, .blue)
        case .forest: (Color(red: 0.03, green: 0.07, blue: 0.04), .green, .teal)
        case .graphite: (Color(white: 0.08), Color(white: 0.35), Color(white: 0.2))
        case .black: (.black, .clear, .clear)
        }
    }
}

enum TemperatureUnit: String, Codable, CaseIterable, Identifiable {
    case fahrenheit, celsius
    var id: Self { self }
    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
}

/// Codable stand-in for Color.
struct RGBAColor: Codable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    init(_ color: Color) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
        red = r; green = g; blue = b; alpha = a
    }

    var color: Color { Color(red: red, green: green, blue: blue, opacity: alpha) }

    static let swatches: [RGBAColor] = [
        .init(.white), .init(Color(red: 1, green: 0.55, blue: 0.35)), .init(.orange), .init(.yellow),
        .init(.mint), .init(.cyan), .init(.blue), .init(.purple), .init(.pink), .init(.red),
    ]
}

extension Binding where Value == RGBAColor {
    /// Bridges a stored color to SwiftUI's ColorPicker.
    var color: Binding<Color> {
        Binding<Color>(get: { wrappedValue.color }, set: { wrappedValue = RGBAColor($0) })
    }
}
