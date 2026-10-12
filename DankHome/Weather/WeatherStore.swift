//
//  WeatherStore.swift
//  DankHome
//

import CoreLocation
import MapKit
import SwiftUI

struct HourForecast: Identifiable {
    let id: Date
    var temperature: Double
    var code: Int
    var isDay: Bool
}

struct CurrentWeather {
    var temperature: Double
    var feelsLike: Double
    var humidity: Double
    var code: Int
    var isDay: Bool
    var high: Double
    var low: Double
}

/// Fetches weather from Open-Meteo (free, no API key). Temperatures are kept in °C;
/// views convert using the user's unit setting.
@Observable
final class WeatherStore {
    private(set) var current: CurrentWeather?
    private(set) var hours: [HourForecast] = []
    private(set) var placeName = ""
    /// Sunrise and sunset for today and tomorrow.
    private(set) var sunTimes: [SunTimes] = []
    private(set) var errorMessage: String?

    @ObservationIgnored private let locationManager = CLLocationManager()

    func refresh(_ prefs: Preferences) async {
        guard let location = await location(for: prefs) else {
            errorMessage = prefs.useCurrentLocation
                ? "Allow location access or pick a city in Settings."
                : "Pick a city in Settings."
            return
        }
        do {
            try await fetch(latitude: location.latitude, longitude: location.longitude)
            errorMessage = nil
        } catch {
            errorMessage = "Weather unavailable"
        }
    }

    private func location(for prefs: Preferences) async -> CLLocationCoordinate2D? {
        if !prefs.useCurrentLocation {
            guard !prefs.cityName.isEmpty else { return nil }
            placeName = prefs.cityName
            return CLLocationCoordinate2D(latitude: prefs.cityLatitude, longitude: prefs.cityLongitude)
        }
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    placeName = await Self.cityName(for: location) ?? "Current Location"
                    return location.coordinate
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
            }
        } catch {}
        return nil
    }

    private static func cityName(for location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        return try? await request.mapItems.first?.addressRepresentations?.cityName
    }

    private func fetch(latitude: Double, longitude: Double) async throws {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(latitude)"),
            URLQueryItem(name: "longitude", value: "\(longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            URLQueryItem(name: "timeformat", value: "unixtime"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "2"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)

        current = CurrentWeather(
            temperature: response.current.temperature_2m,
            feelsLike: response.current.apparent_temperature,
            humidity: response.current.relative_humidity_2m,
            code: response.current.weather_code,
            isDay: response.current.is_day == 1,
            high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
            low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m
        )

        if let sunrise = response.daily.sunrise, let sunset = response.daily.sunset {
            sunTimes = zip(sunrise, sunset).map {
                SunTimes(sunrise: Date(timeIntervalSince1970: $0), sunset: Date(timeIntervalSince1970: $1))
            }
        }

        let now = Date.now.addingTimeInterval(-3600)
        hours = response.hourly.time.indices
            .map { index in
                HourForecast(
                    id: Date(timeIntervalSince1970: response.hourly.time[index]),
                    temperature: response.hourly.temperature_2m[index],
                    code: response.hourly.weather_code[index],
                    isDay: response.hourly.is_day[index] == 1
                )
            }
            .filter { $0.id > now }
            .prefix(12)
            .map { $0 }
    }

    /// City search for the Settings page.
    static func searchCities(_ query: String) async -> [City] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [URLQueryItem(name: "name", value: query), URLQueryItem(name: "count", value: "8")]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(CitySearchResponse.self, from: data) else { return [] }
        return response.results ?? []
    }
}

// MARK: - Weather codes (WMO)

enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 66: "cloud.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 80, 81: isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61, 63, 66: "Rain"
        case 65, 67: "Heavy Rain"
        case 71...77, 85, 86: "Snow"
        case 80...82: "Showers"
        case 95...99: "Thunderstorms"
        default: "—"
        }
    }
}

// MARK: - API models

struct City: Decodable, Identifiable, Hashable {
    var id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var country: String?
    var admin1: String?

    var detail: String { [admin1, country].compactMap { $0 }.joined(separator: ", ") }
}

private struct CitySearchResponse: Decodable {
    var results: [City]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        var temperature_2m: Double
        var apparent_temperature: Double
        var relative_humidity_2m: Double
        var weather_code: Int
        var is_day: Int
    }

    struct Hourly: Decodable {
        var time: [TimeInterval]
        var temperature_2m: [Double]
        var weather_code: [Int]
        var is_day: [Int]
    }

    struct Daily: Decodable {
        var temperature_2m_max: [Double]
        var temperature_2m_min: [Double]
        var sunrise: [TimeInterval]?
        var sunset: [TimeInterval]?
    }

    var current: Current
    var hourly: Hourly
    var daily: Daily
}
