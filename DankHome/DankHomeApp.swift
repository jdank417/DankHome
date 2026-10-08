//
//  DankHomeApp.swift
//  DankHome
//
//  Created by Jason Dank on 10/8/26.
//

import SwiftUI

@main
struct DankHomeApp: App {
    @State private var home = HomeStore()
    @State private var music = MusicStore()
    @State private var settings = AppSettings()
    @State private var weather = WeatherStore()
    @State private var idle = IdleMonitor()

    var body: some Scene {
        WindowGroup {
            ZStack {
                DashboardView()
                if idle.isSleeping {
                    NightClockView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .background(ActivityTracker(monitor: idle))
            .environment(home)
            .environment(music)
            .environment(settings)
            .environment(weather)
            .environment(idle)
            .fontDesign(settings.prefs.appFont.design)
            .tint(settings.prefs.accent.color)
            .onChange(of: settings.prefs.keepAwake, initial: true) { _, keepAwake in
                // Wall-mounted: keep the screen awake while the app is open.
                UIApplication.shared.isIdleTimerDisabled = keepAwake
            }
            // Re-fetch weather every 30 minutes, and right away when its settings change.
            .task(id: settings.prefs.weatherKey) {
                while !Task.isCancelled {
                    await weather.refresh(settings.prefs)
                    try? await Task.sleep(for: .seconds(30 * 60))
                }
            }
            // Check for idle every few seconds to start the night clock.
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    idle.check(settings.prefs)
                }
            }
        }
    }
}
